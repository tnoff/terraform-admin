# ==============================================================================
# GitHub OIDC identities for terraform's dns/ stack (tnoff/terraform#135)
#
# Replaces the stored terraform-dns-ci API key for dns/ with two federated
# service users, chosen by the run's GitHub `sub` (the trust rules are in
# oidc-spike.tf, next to the trust they extend):
#
#   pull_request            -> dns plan user   READ the dns state, cluster path
#   push to main            -> dns apply user  WRITE the dns state, cluster path
#
# Anything else matches no rule, so the token exchange is refused.
#
# The privileges are exactly what terraform-dns-ci holds today (write on the dns
# state bucket plus the bastion/OKE path, in-cluster read of Services via
# bootstrap/), split by who is asking. dns/ gains nothing and loses a stored
# key. Two things follow from that split:
#
#   - the plan user cannot take the state lock (a write), so PR plans run with
#     -lock=false; the apply user can, so applies keep the lock.
#   - every PR in the repo shares the one `pull_request` `sub` (it carries no
#     branch or PR number), and a PR can edit workflow files, so the plan user
#     is what any same-repo PR can act as. That is why it is read-only. Fork PRs
#     get no OIDC token from GitHub at all.
#
# apps/ is deliberately not here: it reads the secret-bearing oci and discord
# state, so a PR-reachable identity for it needs a decision first.
# ==============================================================================

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
  # name -> what it may do to state. The cluster path is the same for both.
  dns_oidc_identities = {
    plan = {
      name        = "terraform-dns-plan-oidc"
      description = "Federated service user for dns/ PR plans (GitHub pull_request runs): read-only"
      state_verb  = "read"
      workspaces  = var.dns_oidc_plan_read_workspaces
    }
    apply = {
      name        = "terraform-dns-apply-oidc"
      description = "Federated service user for dns/ applies (GitHub push-to-main runs)"
      state_verb  = "manage"
      workspaces  = var.dns_oidc_apply_write_workspaces
    }
  }
}

resource "oci_identity_domains_user" "dns_oidc" {
  for_each = local.dns_oidc_identities

  idcs_endpoint = local.oidc_spike_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User"]
  user_name     = each.value.name
  description   = each.value.description

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }
}

resource "oci_identity_domains_group" "dns_oidc" {
  for_each = local.dns_oidc_identities

  idcs_endpoint = local.oidc_spike_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = each.value.name

  members {
    type  = "User"
    value = oci_identity_domains_user.dns_oidc[each.key].id
  }
}

resource "oci_identity_policy" "dns_oidc" {
  for_each = local.dns_oidc_identities

  compartment_id = var.oci_tenancy_ocid
  description    = each.value.description
  name           = "${each.value.name}-policy"

  statements = concat(
    [
      "Allow group ${oci_identity_domains_group.dns_oidc[each.key].display_name} to ${each.value.state_verb} objects in tenancy where any {${join(", ", [for w in each.value.workspaces : "target.bucket.name = '${var.state_bucket_prefix}-${w}'"])}}",
    ],
    [
      for grant in local.cluster_path_grants :
      "Allow group ${oci_identity_domains_group.dns_oidc[each.key].display_name} to ${grant} in compartment ${var.cluster_ci_compartment_name}"
    ],
  )

  freeform_tags = {
    "Purpose"   = each.value.name
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}
