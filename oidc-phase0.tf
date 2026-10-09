# ==============================================================================
# Phase 0 experiment for tnoff/terraform#135 -- THROWAWAY, delete after reading
# the results in the issue.
#
# Question: the GitHub trust is unique (Oracle documents `issuer` as
# `uniqueness: server`), so a token has to select a stack's identity through a
# claim a rule can match. Can a rule match claims other than `sub`, and what wins
# when several rules match one token?
#
# Two service users with NO groups and NO policies: they can be impersonated and
# can do nothing, so adding rules that map to them widens no access. Which user a
# test token resolves to (the `sub` of the OCI session token is the user's OCID)
# says which rule matched.
#
#   phase0_aud  <- rule `aud eq oidc-phase0-aud`
#                  the job chooses its own audience, so this claim is NOT safe to
#                  gate anything that writes; it is what a read-only plan
#                  identity could use.
#   phase0_jwr  <- rule `job_workflow_ref eq <this workflow>@<branch>`
#                  carries the workflow file and the ref, which a pull request
#                  cannot make end in refs/heads/main: the candidate for per-stack
#                  apply identities.
#
# The rules are appended to the existing trust in oidc-spike.tf, after the `sub`
# rules, so a token that matches a `sub` rule AND a new rule shows whether the
# first or the last match wins.
# ==============================================================================

locals {
  oidc_phase0_aud = "oidc-phase0-aud"

  # The throwaway workflow in tnoff/terraform, on one specific throwaway branch.
  oidc_phase0_jwr = "tnoff/terraform/.github/workflows/oidc-phase0.yml@refs/heads/spike/oidc-phase0"

  oidc_phase0_users = {
    aud = "terraform-oidc-phase0-aud"
    jwr = "terraform-oidc-phase0-jwr"
  }
}

resource "oci_identity_domains_user" "oidc_phase0" {
  for_each = local.oidc_phase0_users

  idcs_endpoint = local.oidc_spike_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User"]
  user_name     = each.value
  description   = "Phase 0 experiment user, no permissions (tnoff/terraform#135)"

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }
}
