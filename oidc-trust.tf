# ==============================================================================
# GitHub OIDC -> OCI identity propagation: the exchange app and the trust
# (tnoff/terraform#135)
#
# Lets a GitHub Actions job exchange its signed OIDC token for a one-hour OCI
# session token (UPST) instead of holding an API key. The per-stack plan and apply
# service users are in github-oidc.tf; this file is what they all share.
#
#   exchange app   confidential app the job authenticates to /oauth2/v1/token
#                  with (client id + secret, pushed to tnoff/terraform as the
#                  OIDC_EXCHANGE_* secrets in main.tf). No admin roles, per Oracle's
#                  least-privilege guidance; authorised by the trust below.
#   trust          ONE per issuer. Validates GitHub's issuer + signature, then maps
#                  a claim of the token to a service user by rule (the dynamic
#                  block below is generated from github-oidc.tf).
#
# The live objects keep their spike-era names (display name
# `terraform-oidc-spike-exchange`, trust `github-actions-oidc-spike`): renaming
# either would recreate it and rotate the client secret mid-pipeline. Only the
# Terraform addresses changed, with the `moved` blocks below (no OCI change).
#
# Terraform CANNOT read the trust's rules back (Oracle returns
# `impersonation_service_users` only on request), so `plan` shows no drift when the
# live rules differ, and removing or reordering a rule silently does not apply.
# Apply any rule change with
#   terraform apply -replace=oci_identity_domains_identity_propagation_trust.github_actions \
#                   -target=oci_identity_domains_identity_propagation_trust.github_actions
# and verify with an admin read of the live rules (see the header of github-oidc.tf).
# ==============================================================================

locals {
  oidc_issuer = "https://token.actions.githubusercontent.com"
}

# The identity domain the trust, app and service user live in. The tenancy has a
# single domain (Default); looking it up avoids hardcoding its endpoint.
data "oci_identity_domains" "default" {
  compartment_id = var.oci_tenancy_ocid
  display_name   = "Default"
}

locals {
  oidc_domain_endpoint = data.oci_identity_domains.default.domains[0].url
}

# The app the CI job authenticates as to call the token endpoint. Its client
# secret is only useful together with a GitHub token the trust accepts.
resource "oci_identity_domains_app" "oidc_exchange" {
  idcs_endpoint   = local.oidc_domain_endpoint
  schemas         = ["urn:ietf:params:scim:schemas:oracle:idcs:App"]
  display_name    = "terraform-oidc-spike-exchange"
  description     = "Token-exchange client for the GitHub OIDC federation (tnoff/terraform#135)"
  active          = true
  show_in_my_apps = false

  based_on_template {
    value         = "CustomWebAppTemplateId"
    well_known_id = "CustomWebAppTemplateId"
  }

  is_oauth_client = true
  client_type     = "confidential"
  allowed_grants  = ["client_credentials"]
}

resource "oci_identity_domains_identity_propagation_trust" "github_actions" {
  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]
  name          = "github-actions-oidc-spike"
  description   = "Maps GitHub Actions tokens to OCI service users: per stack, a plan and an apply identity (tnoff/terraform#135)"
  type          = "JWT"
  active        = true

  issuer              = local.oidc_issuer
  public_key_endpoint = "${local.oidc_issuer}/.well-known/jwks"

  # Only the exchange app may present a GitHub token to this trust.
  oauth_clients = [oci_identity_domains_app.oidc_exchange.name]

  # The UPST impersonates the service user instead of a federated human.
  allow_impersonation = true
  subject_type        = "User"

  # Per-stack identities (github-oidc.tf): `aud` for plan, `job_workflow_ref` at
  # main for apply. Read the header there before adding or changing a rule.
  dynamic "impersonation_service_users" {
    for_each = local.oidc_identities

    content {
      rule  = impersonation_service_users.value.rule
      value = oci_identity_domains_user.oidc[impersonation_service_users.key].id
    }
  }
}

output "oidc_domain_endpoint" {
  description = "Identity domain URL the token exchange is POSTed to (<this>/oauth2/v1/token)"
  value       = local.oidc_domain_endpoint
}

output "oidc_exchange_client_id" {
  description = "Client id of the token-exchange app"
  value       = oci_identity_domains_app.oidc_exchange.name
}

output "oidc_exchange_client_secret" {
  description = "Client secret of the token-exchange app. Already pushed to tnoff/terraform as OIDC_EXCHANGE_CLIENT_SECRET via terraform_ci_vars; this output is for reading it locally."
  value       = oci_identity_domains_app.oidc_exchange.client_secret
  sensitive   = true
}

moved {
  from = oci_identity_domains_app.oidc_spike_exchange
  to   = oci_identity_domains_app.oidc_exchange
}

moved {
  from = oci_identity_domains_identity_propagation_trust.oidc_spike
  to   = oci_identity_domains_identity_propagation_trust.github_actions
}
