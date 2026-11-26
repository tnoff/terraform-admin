# ==============================================================================
# Kubernetes ServiceAccount -> OCI token exchange app (tnoff/terraform#191)
#
# Lets a pod in the OKE cluster exchange its projected ServiceAccount token for a
# short-lived OCI resource principal session token (RPST) instead of holding an API
# key. This file keeps only the exchange app: a confidential client whose id and secret
# are credentials, so they stay with the other credentials here. It is NOT the GitHub
# one (oidc-exchange.tf), so a leaked secret on one side cannot reach the other trust.
# No admin roles.
#
# The `k8s-workloads` trust it is listed on, and the hosted key set bucket the trust
# fetches signing keys from, are in tnoff/terraform (`trust/` and `oci/`). The client id
# reaches `trust/` as TF_VAR_k8s_exchange_client_id; replacing this app (rotation) changes
# the id, so `trust/` must be applied afterwards (see docs/secret-rotation.md).
# ==============================================================================

resource "oci_identity_domains_app" "k8s_exchange" {
  idcs_endpoint   = local.oidc_domain_endpoint
  schemas         = ["urn:ietf:params:scim:schemas:oracle:idcs:App"]
  display_name    = "k8s-workload-exchange"
  description     = "Token-exchange client for in-cluster ServiceAccount federation (tnoff/terraform#191)"
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

output "k8s_exchange_client_id" {
  description = "Client id of the in-cluster token-exchange app"
  value       = oci_identity_domains_app.k8s_exchange.name
}

output "k8s_exchange_client_secret" {
  description = "Client secret of the in-cluster token-exchange app. Already pushed to tnoff/terraform as TF_VAR_k8s_exchange_client_secret via terraform_ci_vars, for apps/'s rpst-exchange-creds Secret; this output is for reading it locally."
  value       = oci_identity_domains_app.k8s_exchange.client_secret
  sensitive   = true
}
