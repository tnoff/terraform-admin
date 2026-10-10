# ==============================================================================
# THROWAWAY: OCIR federation spike (tnoff/terraform#180). Delete after the spike.
#
# Question: can a GitHub job log in to the container registry (OCIR) as a federated
# service user, instead of using a stored auth token? OCIR rejected the plan user
# with USER_DISABLED for any password, because service users have every credential
# capability off, including `can-use-auth-tokens`. This user has that one turned on,
# so the registry will say something about the credential itself.
#
# Mapped by a dedicated audience, which is only acceptable because the user can
# pull one repo and nothing else (an `aud` rule must never reach a write identity).
# The trust rule is added to the trust's static rules below and to the expected set
# in oidc-trust.tf's check, so the check stays quiet.
# ==============================================================================

locals {
  ocir_spike_rule = "aud eq oidc-spike-ocir"
  ocir_spike_repo = "ocir_cleanup"
}

resource "oci_identity_domains_user" "ocir_spike" {
  idcs_endpoint = local.oidc_domain_endpoint
  schemas = [
    "urn:ietf:params:scim:schemas:core:2.0:User",
    "urn:ietf:params:scim:schemas:oracle:idcs:extension:capabilities:User",
  ]
  user_name   = "terraform-ocir-spike"
  description = "Throwaway service user for the OCIR federation spike (tnoff/terraform#180)"

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }

  urnietfparamsscimschemasoracleidcsextensioncapabilities_user {
    can_use_auth_tokens = true
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
  description    = "Throwaway policy for the OCIR federation spike: pull one repo"
  name           = "terraform-ocir-spike-policy"

  statements = [
    "Allow group ${oci_identity_domains_group.ocir_spike.display_name} to read repos in compartment ${var.cluster_ci_compartment_name} where target.repo.name = '${local.ocir_spike_repo}'",
  ]

  freeform_tags = {
    "Purpose"   = "terraform-ocir-spike"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}
