# ==============================================================================
# GitHub OIDC identities for terraform's CI stacks (tnoff/terraform#135)
#
# Replaces the stored per-stack API keys with federated service users. Each stack
# has a PLAN identity (read-only, used by pull_request runs) and an APPLY
# identity (used by applies on main). The trust (tnoff/terraform trust/) hands a token the
# user whose rule it matches. Phase 0 measured how, and set the rules below:
#
#   plan   aud eq oidc-plan-<stack>
#          The audience is chosen by the requesting job, so ANY job, including a
#          malicious pull request, can ask for ANY stack's plan identity. That is
#          only acceptable because every plan identity is read-only. An `aud`
#          rule must never map to anything that writes: in the overlap test the
#          `aud` rule beat both a `sub` rule and a `job_workflow_ref` rule.
#
#   apply  job_workflow_ref eq <repo>/.github/workflows/apply-<stack>.yml@refs/heads/main
#          Names the stack's reusable workflow and the ref. A pull request's value
#          ends in refs/pull/N/merge, so it cannot produce this one. Each stack
#          needs its own apply-<stack>.yml, called from apply.yml.
#
#   env    sub eq repo:<owner>@<id>/<repo>@<id>:environment:<name>
#          For stacks applied behind a protected GitHub Environment (bootstrap). Only a job
#          that names the environment gets this `sub`, and GitHub does not start such a job
#          until the environment's branch policy and required reviewers allow it, so a pull
#          request cannot reach it (neither can a push to another branch). The same shape
#          as the TechDocs environment rule in tnoff/terraform oci/. A stack with an
#          explicit `rule` in local.oidc_stacks uses it instead of the two defaults above.
#
# Rules must not overlap: the winner when several match is not decided by list
# position, so an intended token should match exactly one rule, and an accidental
# overlap must resolve to a lower-privilege identity (a main-push apply token that
# asks for a plan audience gets the plan user, which is the safe direction).
#
# Privileges are what each stack's scoped API-key user holds today, split by who
# is asking. Adding a stack is one entry in local.oidc_stacks, one reusable apply
# workflow, and (for stacks that reach the cluster) a bootstrap/ RBAC binding.
#
# Removing an identity takes TWO applies. Identity Domains refuses to delete a
# user that a trust rule still points at (DeleteUser returned 400 with no
# message when the Phase 0 users were removed in the same apply as the rules that
# referenced them), and Terraform does not order the trust's update before the
# delete of a resource that has left the configuration: it orders destroys after
# destroys, not after updates. So drop the identity's rule (keep the user) in one
# apply, then delete the user in the next. If it happens anyway, `terraform apply
# -target=oci_identity_domains_identity_propagation_trust.github_actions` first, then
# a full apply.
# ==============================================================================

variable "oidc_github_repo" {
  description = "GitHub repository (owner/name) whose reusable apply workflows the apply rules are bound to"
  type        = string
  default     = "tnoff/terraform"
}

variable "oidc_github_owner_id" {
  description = "Numeric id of the GitHub owner (gh api users/<owner> --jq .id), for the immutable subject of environment rules"
  type        = number
  default     = 1326564
}

variable "oidc_github_repo_id" {
  description = "Numeric id of oidc_github_repo (gh api repos/<owner>/<repo> --jq .id), for the immutable subject of environment rules"
  type        = number
  default     = 1356736164
}

variable "dns_oidc_plan_read_workspaces" {
  description = "State buckets the dns plan user (pull_request runs) may READ. Read-only on purpose."
  type        = list(string)
  default     = ["dns"]
}

variable "dns_oidc_apply_write_workspaces" {
  description = "State buckets the dns apply user (push-to-main runs) may READ AND WRITE."
  type        = list(string)
  default     = ["dns"]
}

locals {
  # stack -> mode -> what that identity may do. cluster_path adds the bastion/OKE
  # grants (stacks that talk to the cluster); the in-cluster permissions are
  # bound to the identity's IAM group in terraform/bootstrap.
  # Subject prefix of a job in this repo, with the owner and repo ids so a renamed or
  # recreated repo does not inherit access: repo:tnoff@<id>/terraform@<id>
  oidc_repo_subject = "repo:${split("/", var.oidc_github_repo)[0]}@${var.oidc_github_owner_id}/${split("/", var.oidc_github_repo)[1]}@${var.oidc_github_repo_id}"

  oidc_stacks = {
    dns = {
      plan = {
        description  = "Federated service user for dns/ PR plans (GitHub pull_request runs): read-only"
        state_verb   = "read"
        workspaces   = var.dns_oidc_plan_read_workspaces
        cluster_path = true
      }
      apply = {
        description  = "Federated service user for dns/ applies (GitHub push-to-main runs)"
        state_verb   = "manage"
        workspaces   = var.dns_oidc_apply_write_workspaces
        cluster_path = true
      }
    }

    # discord/ reads no other stack's state and does not touch the cluster, so each
    # identity gets its own state bucket and nothing else: what terraform-discord-ci
    # holds today, split by who is asking.
    discord = {
      plan = {
        description  = "Federated service user for discord/ PR plans (GitHub pull_request runs): read-only"
        state_verb   = "read"
        workspaces   = ["discord"]
        cluster_path = false
      }
      apply = {
        description  = "Federated service user for discord/ applies (GitHub push-to-main runs)"
        state_verb   = "manage"
        workspaces   = ["discord"]
        cluster_path = false
      }
    }

    # infra/ reads the oci and discord stacks through terraform_remote_state (oci's
    # outputs feed the GitLab/OCIR variables, discord's the CI-alerts webhook), so
    # both identities also READ those two buckets: what terraform-infra-ci holds today,
    # split by who is asking. Those states hold secrets (bot keys, webhook URLs); the
    # plan identity is reachable by any job, which is the exposure the issue accepted
    # because PR plan jobs already hold terraform-infra-ci's key for the same reads.
    infra = {
      plan = {
        description  = "Federated service user for infra/ PR plans (GitHub pull_request runs): read-only"
        state_verb   = "read"
        workspaces   = ["infra"]
        cluster_path = false
        read_extra   = ["oci", "discord"]
      }
      apply = {
        description  = "Federated service user for infra/ applies (GitHub push-to-main runs)"
        state_verb   = "manage"
        workspaces   = ["infra"]
        cluster_path = false
        read_extra   = ["oci", "discord"]
      }
    }

    # apps/ renders Secrets and ConfigMaps into the cluster and reads the oci and
    # discord state. Its cluster permissions are NOT granted here: OKE authorises by
    # RBAC, bound to these identities' IAM groups in terraform/bootstrap
    # (operator-applied). The plan group gets read-only roles (get/list Secrets and
    # ConfigMaps in the namespaces apps/ writes to), the apply group the existing
    # write tiers. The plan identity is reachable by any job, so a pull request can
    # read those Secrets: the exposure the issue accepted, because PR plan jobs
    # already hold terraform-cluster-ci's key, which can read and write them.
    apps = {
      plan = {
        description  = "Federated service user for apps/ PR plans (GitHub pull_request runs): read-only"
        state_verb   = "read"
        workspaces   = ["apps"]
        cluster_path = true
        read_extra   = ["oci", "discord"]
      }
      apply = {
        description  = "Federated service user for apps/ applies (GitHub push-to-main runs)"
        state_verb   = "manage"
        workspaces   = ["apps"]
        cluster_path = true
        read_extra   = ["oci", "discord"]
      }
    }

    # oci/ is the stack the admin key exists for: it manages IAM, networking, OKE,
    # buckets, vaults and OCIR. The apply identity therefore holds
    # `manage all-resources`, reachable only by a push-to-main run of
    # apply-oci.yml. The plan identity is reachable by ANY job (see the header), so
    # it gets READ on the resource families the stack manages and nothing broader:
    # not `read all-resources`, which would let a pull request read every state
    # bucket's objects and vault secrets. It reads the oci state bucket only. If a
    # plan fails with a 404 on a family, add that family here; OCI reports an
    # unauthorised read as not found.
    oci = {
      plan = {
        description  = "Federated service user for oci/ PR plans (GitHub pull_request runs): read-only"
        state_verb   = "read"
        workspaces   = ["oci"]
        cluster_path = false
        tenancy_grants = [
          "read users", "read groups", "read policies", "read compartments", "read tag-namespaces",
          "read virtual-network-family", "read cluster-family", "read bastion-family",
          "read vaults", "read keys", "read repos", "read buckets", "read objectstorage-namespaces",
          # oci/ manages oci_identity_network_source.oke_pods. Without this the plan
          # cannot see it (OCI answers the denied read as not found) and plans a create.
          "read network-sources",
          # oci/ owns the GitHub trust and the federated push/TechDocs identities, and looks the
          # identity domain up by name (data.oci_identity_domains). Without this the list comes
          # back empty rather than denied, and the plan fails indexing it. Names and URLs only:
          # deliberately not `read domains`, which any pull request could use to read the
          # domain's objects. Widen only if a plan still fails on the domain's own objects.
          "inspect domains",
        ]
      }
      apply = {
        description    = "Federated service user for oci/ applies (GitHub push-to-main runs): manage all-resources"
        state_verb     = "manage"
        workspaces     = ["oci"]
        cluster_path   = false
        tenancy_grants = ["manage all-resources"]
      }
    }

    # trust/ owns the one GitHub identity-propagation trust. Identity Domains does not let
    # a narrow IAM grant read a trust: users and groups are covered by `read users`/`read
    # groups`, but apps and trusts are not (GetIdentityPropagationTrust returns 401 for the
    # oci plan identity). A plan identity is reachable by ANY job, so it cannot be given the
    # grants that would work (`read all-resources` exposes every state bucket and vault
    # secret to a pull request). trust/ therefore plans with -refresh=false: the plan
    # identity only reads the trust and oci state buckets (the trust takes oci's rules
    # through remote state) and never touches the domain. The apply identity needs
    # `manage all-resources` for the same reason the oci one does, and is reachable by the
    # same gate (a push-to-main run of apply-trust.yml).
    trust = {
      plan = {
        description  = "Federated service user for trust/ PR plans (GitHub pull_request runs): read-only, no domain access"
        state_verb   = "read"
        workspaces   = ["trust"]
        cluster_path = false
        read_extra   = ["oci"]
      }
      apply = {
        description    = "Federated service user for trust/ applies (GitHub push-to-main runs): manage all-resources"
        state_verb     = "manage"
        workspaces     = ["trust"]
        cluster_path   = false
        read_extra     = ["oci"]
        tenancy_grants = ["manage all-resources"]
      }
    }

    # bootstrap/ (namespaces, the RBAC bindings for the apps/dns CI groups, the Flux install),
    # applied from CI behind protected GitHub Environments instead of from a workstation.
    # Neither identity is reachable from a pull request: each is selected by the `sub` of a
    # job that names its Environment (which is restricted to main, and for apply needs a
    # reviewer). There is no PR plan identity on purpose: a plan reads the flux-system GitHub
    # App key Secret, and a plan identity any pull request could use could print it.
    # Both reach the cluster through the bastion. Plan gets `use clusters` (the cluster_path
    # set) and only reads; the in-cluster read access is bound by bootstrap itself, for the
    # plan group, once this exists. Apply gets `manage clusters`, which OKE maps to
    # cluster-admin (`use clusters` does not): it creates namespaces, RBAC and Flux. That is
    # no more than the oci apply identity already holds through `manage all-resources`.
    # bootstrap reads infra's state for the Flux deploy token.
    bootstrap = {
      plan = {
        description  = "Federated service user for bootstrap/ plans (main only, bootstrap-plan Environment): read-only"
        state_verb   = "read"
        workspaces   = ["bootstrap"]
        cluster_path = true
        read_extra   = ["infra"]
        # bootstrap/ binds the other stacks' IAM groups in the cluster's RBAC and looks them up
        # by name, so it needs to read groups (ids and names only). Environment-gated, so no
        # pull request reaches it.
        tenancy_grants = ["read groups"]
        rule           = "sub eq ${local.oidc_repo_subject}:environment:bootstrap-plan"
      }
      apply = {
        description        = "Federated service user for bootstrap/ applies (main only, bootstrap-apply Environment with a required reviewer): manage clusters"
        state_verb         = "manage"
        workspaces         = ["bootstrap"]
        cluster_path       = true
        read_extra         = ["infra"]
        compartment_grants = ["manage clusters"]
        tenancy_grants     = ["read groups"]
        rule               = "sub eq ${local.oidc_repo_subject}:environment:bootstrap-apply"
      }
    }
  }

  # One entry per identity, keyed "<stack>-<mode>". The names are unchanged from
  # the first, dns-only version (terraform-dns-plan-oidc, terraform-dns-apply-oidc).
  oidc_identities = merge([
    for stack, modes in local.oidc_stacks : {
      for mode, cfg in modes : "${stack}-${mode}" => merge(cfg, {
        stack = stack
        mode  = mode
        name  = "terraform-${stack}-${mode}-oidc"
        # The trust rule that selects this identity (see tnoff/terraform trust/).
        rule = try(cfg.rule, (mode == "plan"
          ? "aud eq oidc-plan-${stack}"
        : "job_workflow_ref eq ${var.oidc_github_repo}/.github/workflows/apply-${stack}.yml@refs/heads/main"))
      })
    }
  ]...)
}

# Trust rule -> service user id for every identity above. The trust itself is owned by
# tnoff/terraform's oci/ stack, which takes this map as TF_VAR_oidc_stack_rules (published to
# CI in terraform_ci_vars, and to the operator's .envrc in admin_secrets_bundle).
locals {
  oidc_stack_rules = {
    for k, v in local.oidc_identities : v.rule => oci_identity_domains_user.oidc[k].id
  }
}

# IDCS returns some attributes only when a read asks for them by name (the same
# reason the trust's rules cannot be read back, see tnoff/terraform trust/README.md). For these
# users and groups that made every plan show the same no-op changes after an
# apply: `schemas` listing the extension URNs the API adds, and each group's
# `members` as new. state show confirms the group has no members and the
# dynamic:Group schema, and meta.last_modified never moves, so nothing is being
# changed. The identity users and groups here, and the image-push and TechDocs ones in
# tnoff/terraform oci/, therefore ignore those attributes. A group is replaced
# when its user's id changes, so its membership still follows a replaced user.
resource "oci_identity_domains_user" "oidc" {
  for_each = local.oidc_identities

  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User"]
  user_name     = each.value.name
  description   = each.value.description

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }

  # IDCS adds the extension schemas the resource's blocks imply, so state
  # never matches this list; see the note above the first user in github-oidc.tf.
  lifecycle {
    ignore_changes = [schemas]
  }
}

resource "oci_identity_domains_group" "oidc" {
  for_each = local.oidc_identities

  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = each.value.name

  members {
    type  = "User"
    value = oci_identity_domains_user.oidc[each.key].id
  }

  # members and the dynamic-group schema are not returned on read (see the note
  # in github-oidc.tf). The user's id only changes when it is replaced, which
  # recreates the group so the membership follows it.
  lifecycle {
    ignore_changes       = [schemas, members]
    replace_triggered_by = [oci_identity_domains_user.oidc[each.key].id]
  }
}

resource "oci_identity_policy" "oidc" {
  for_each = local.oidc_identities

  compartment_id = var.oci_tenancy_ocid
  description    = each.value.description
  name           = "${each.value.name}-policy"

  statements = concat(
    [
      "Allow group ${oci_identity_domains_group.oidc[each.key].display_name} to ${each.value.state_verb} objects in tenancy where any {${join(", ", [for w in each.value.workspaces : "target.bucket.name = '${var.state_bucket_prefix}-${w}'"])}}",
    ],
    [
      for grant in(each.value.cluster_path ? local.cluster_path_grants : []) :
      "Allow group ${oci_identity_domains_group.oidc[each.key].display_name} to ${grant} in compartment ${var.cluster_ci_compartment_name}"
    ],
    [
      for grant in try(each.value.compartment_grants, []) :
      "Allow group ${oci_identity_domains_group.oidc[each.key].display_name} to ${grant} in compartment ${var.cluster_ci_compartment_name}"
    ],
    length(try(each.value.read_extra, [])) == 0 ? [] : [
      "Allow group ${oci_identity_domains_group.oidc[each.key].display_name} to read objects in tenancy where any {${join(", ", [for w in each.value.read_extra : "target.bucket.name = '${var.state_bucket_prefix}-${w}'"])}}",
    ],
    [
      for grant in try(each.value.tenancy_grants, []) :
      "Allow group ${oci_identity_domains_group.oidc[each.key].display_name} to ${grant} in tenancy"
    ],
  )

  freeform_tags = {
    "Purpose"   = each.value.name
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

# The first version of this file was dns-only and keyed these by mode ("plan",
# "apply") under other resource names. Moving them keeps the same OCI objects;
# without these blocks Terraform would destroy and recreate them, which changes
# the groups' OCIDs that terraform/bootstrap binds in the cluster's RBAC.
moved {
  from = oci_identity_domains_user.dns_oidc["plan"]
  to   = oci_identity_domains_user.oidc["dns-plan"]
}

moved {
  from = oci_identity_domains_user.dns_oidc["apply"]
  to   = oci_identity_domains_user.oidc["dns-apply"]
}

moved {
  from = oci_identity_domains_group.dns_oidc["plan"]
  to   = oci_identity_domains_group.oidc["dns-plan"]
}

moved {
  from = oci_identity_domains_group.dns_oidc["apply"]
  to   = oci_identity_domains_group.oidc["dns-apply"]
}

moved {
  from = oci_identity_policy.dns_oidc["plan"]
  to   = oci_identity_policy.oidc["dns-plan"]
}

moved {
  from = oci_identity_policy.dns_oidc["apply"]
  to   = oci_identity_policy.oidc["dns-apply"]
}
