# ==============================================================================
# THROWAWAY: OCIR federation spike (tnoff/terraform#180). Delete after the spike.
#
# Question: can a GitHub job PUSH images to OCIR as a federated service user, with no
# stored auth token? The read half is proven: a signed request from a session token
# to https://<region>.ocir.io/20180419/docker/token returns a bearer token that
# `docker login -u BEARER_TOKEN` accepts (tnoff/terraform#180). This tests a push.
#
# The user is a plain service user (no credential capabilities: the signed-request
# path does not need them). It may manage ONE scratch repo (terraform's oci/ stack
# creates `ocir_spike`) and nothing else.
#
# Selected by an exact-branch `sub`, not by `aud`: it can write, so a pull request
# must not be able to reach it. The `sub` of a push to the spike branch is
# `<prefix>:ref:refs/heads/<branch>`; a pull_request run has `<prefix>:pull_request`.
# The trust rule is in oidc-trust.tf's static block and in the check's expected set.
# ==============================================================================

locals {
  ocir_spike_rule = "sub eq repo:tnoff@1326564/terraform@1356736164:ref:refs/heads/spike/ocir-federation"
  ocir_spike_repo = "ocir_spike"
}

resource "oci_identity_domains_user" "ocir_spike" {
  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User"]
  user_name     = "terraform-ocir-spike"
  description   = "Throwaway service user for the OCIR federation spike (tnoff/terraform#180)"

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }
}

resource "oci_identity_domains_group" "ocir_spike" {
  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = "terraform-ocir-spike"

  members {
    type  = "User"
    value = oci_identity_domains_user.ocir_spike.id
  }
}

resource "oci_identity_policy" "ocir_spike" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Throwaway policy for the OCIR federation spike: manage one scratch repo"
  name           = "terraform-ocir-spike-policy"

  statements = [
    "Allow group ${oci_identity_domains_group.ocir_spike.display_name} to manage repos in compartment ${var.cluster_ci_compartment_name} where target.repo.name = '${local.ocir_spike_repo}'",
  ]

  freeform_tags = {
    "Purpose"   = "terraform-ocir-spike"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}
