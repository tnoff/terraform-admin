# ==============================================================================
# GitHub OIDC spike identity: BEING REMOVED (tnoff/terraform#135 phase 6)
#
# The spike's service user, group and policy. Its trust rule (`sub eq` the spike
# branch) was dropped from the trust in oidc-trust.tf, and the bootstrap/ binding
# and the spike workflow are gone. This file is only kept for one more apply because
# Identity Domains refuses to delete a user a live trust rule still references
# (DeleteUser returns 400): apply the rule's removal first, then delete this file.
# ==============================================================================

variable "oidc_spike_state_read_workspaces" {
  description = "State buckets the spike service user may READ (not write)."
  type        = list(string)
  default     = ["dns"]
}

resource "oci_identity_domains_user" "oidc_spike" {
  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User"]
  user_name     = "terraform-oidc-spike"
  description   = "Throwaway service user for the GitHub OIDC federation spike (tnoff/terraform#135)"

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }
}

resource "oci_identity_domains_group" "oidc_spike" {
  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = "terraform-oidc-spike"

  members {
    type  = "User"
    value = oci_identity_domains_user.oidc_spike.id
  }
}

resource "oci_identity_policy" "oidc_spike" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Throwaway policy for the GitHub OIDC federation spike: read-only on state buckets, plus the bastion/OKE path"
  name           = "terraform-oidc-spike-policy"

  # The cluster path is the same set the cluster/dns CI users hold (see
  # local.cluster_path_grants), so the spike can open a bastion session and ask
  # OKE to authenticate its token. What it may then DO in the cluster is bound
  # in terraform/bootstrap (operator-applied), not here: read Services in
  # ingress-nginx, nothing else.
  statements = concat(
    [
      "Allow group ${oci_identity_domains_group.oidc_spike.display_name} to read objects in tenancy where any {${join(", ", [for w in var.oidc_spike_state_read_workspaces : "target.bucket.name = '${var.state_bucket_prefix}-${w}'"])}}",
    ],
    [
      for grant in local.cluster_path_grants :
      "Allow group ${oci_identity_domains_group.oidc_spike.display_name} to ${grant} in compartment ${var.cluster_ci_compartment_name}"
    ],
  )

  freeform_tags = {
    "Purpose"   = "terraform-oidc-spike"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}
