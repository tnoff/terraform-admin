# ==============================================================================
# GitHub OIDC -> OCI token exchange: the exchange app (tnoff/terraform#135)
#
# Lets a GitHub Actions job exchange its signed OIDC token for a one-hour OCI
# session token (UPST) instead of holding an API key. This file holds the one
# confidential app the job authenticates to /oauth2/v1/token with (client id +
# secret, pushed to tnoff/terraform as the OIDC_EXCHANGE_* secrets in main.tf). No
# admin roles, per Oracle's least-privilege guidance; it is authorised by the trust.
#
# The TRUST itself is in tnoff/terraform's trust/ stack (OCI allows one per issuer, and CI
# applies it), and so are the per-stack plan/apply identities (oci/). This repo keeps only the
# app below: it is what CI logs in WITH, so it stays with the credentials.
#
# The live app keeps its spike-era display name `terraform-oidc-spike-exchange`:
# renaming it would recreate it and rotate the client secret mid-pipeline.
# ==============================================================================

# The identity domain the app lives in. The tenancy has a
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
