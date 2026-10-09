# ==============================================================================
# GitHub OIDC identities for terraform's CI stacks (tnoff/terraform#135)
#
# Replaces the stored per-stack API keys with federated service users. Each stack
# has a PLAN identity (read-only, used by pull_request runs) and an APPLY
# identity (used by applies on main). The trust (oidc-spike.tf) hands a token the
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
# Rules must not overlap: the winner when several match is not decided by list
# position, so an intended token should match exactly one rule, and an accidental
# overlap must resolve to a lower-privilege identity (a main-push apply token that
# asks for a plan audience gets the plan user, which is the safe direction).
#
# Privileges are what each stack's scoped API-key user holds today, split by who
# is asking. Adding a stack is one entry in local.oidc_stacks, one reusable apply
# workflow, and (for stacks that reach the cluster) a bootstrap/ RBAC binding.
#
# apps/ is deliberately not here yet: it reads the secret-bearing oci and discord
# state, so a PR-reachable identity for it needs the grant decision first.
# ==============================================================================

variable "oidc_github_repo" {
  description = "GitHub repository (owner/name) whose reusable apply workflows the apply rules are bound to"
  type        = string
  default     = "tnoff/terraform"
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
  }

  # One entry per identity, keyed "<stack>-<mode>". The names are unchanged from
  # the first, dns-only version (terraform-dns-plan-oidc, terraform-dns-apply-oidc).
  oidc_identities = merge([
    for stack, modes in local.oidc_stacks : {
      for mode, cfg in modes : "${stack}-${mode}" => merge(cfg, {
        stack = stack
        mode  = mode
        name  = "terraform-${stack}-${mode}-oidc"
        # The trust rule that selects this identity (see oidc-spike.tf).
        rule = (mode == "plan"
          ? "aud eq oidc-plan-${stack}"
        : "job_workflow_ref eq ${var.oidc_github_repo}/.github/workflows/apply-${stack}.yml@refs/heads/main")
      })
    }
  ]...)
}

resource "oci_identity_domains_user" "oidc" {
  for_each = local.oidc_identities

  idcs_endpoint = local.oidc_spike_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User"]
  user_name     = each.value.name
  description   = each.value.description

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }
}

resource "oci_identity_domains_group" "oidc" {
  for_each = local.oidc_identities

  idcs_endpoint = local.oidc_spike_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = each.value.name

  members {
    type  = "User"
    value = oci_identity_domains_user.oidc[each.key].id
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
