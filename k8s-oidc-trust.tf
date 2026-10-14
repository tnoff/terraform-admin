# ==============================================================================
# Kubernetes ServiceAccount -> OCI identity propagation (tnoff/terraform#191)
#
# Lets a pod in the OKE cluster exchange its projected ServiceAccount token for a
# short-lived OCI resource principal session token (RPST) instead of holding an API
# key. The basic (non-enhanced) cluster has no workload identity, so the token
# is exchanged against this trust, and the cluster's signing keys are mirrored into a
# public Object Storage bucket by the jwks-publisher CronJob (oke-utilities).
#
#   exchange app   its own confidential app, NOT the GitHub one in oidc-trust.tf, so
#                  a leaked GitHub-side secret cannot reach this trust and the other
#                  way round. No admin roles.
#   trust          ONE for the cluster issuer. Validates the signature against the
#                  hosted key set and propagates the token's `sub` and `iss` as
#                  `ext_sub` / `ext_iss`, which the per-workload policies in
#                  tnoff/terraform oci/ match on:
#                    request.principal.name    = the RPST's workload name
#                    request.principal.ext_sub = system:serviceaccount:<ns>:<name>
#                    request.principal.ext_iss = this issuer
#                  All three are enforced by OCI (verified on #191). `ext_iss` is the
#                  one that matters: the Kubernetes default issuer is identical for
#                  every cluster, and OCI allows one trust per issuer string, so the
#                  issuer claim is the only thing tying a token to this trust.
#
# The trust exchanges any token that verifies against the hosted key set. What a
# workload can DO is decided only by the policies; a workload with no policy gets an
# RPST that can do nothing. Anything that can write the bucket can mint identities,
# which is why the publisher's key is bound to the cluster network (terraform#202).
#
# OCI fetches `public_key_endpoint` on every NEW exchange (no cache). An outage of the
# bucket stops new exchanges immediately and loudly (401), while tokens already issued
# keep working until they expire.
# ==============================================================================

locals {
  # The Kubernetes default `iss` for this cluster's ServiceAccount tokens.
  k8s_oidc_issuer = "https://kubernetes.default.svc.cluster.local"
}

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

resource "oci_identity_domains_identity_propagation_trust" "k8s_workloads" {
  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]
  name          = "k8s-workloads"
  description   = "Maps in-cluster ServiceAccount tokens to OCI resource principals (tnoff/terraform#191)"
  type          = "JWT"
  active        = true

  issuer              = local.k8s_oidc_issuer
  public_key_endpoint = var.k8s_jwks_endpoint_url

  # Only the cluster exchange app may present a ServiceAccount token to this trust.
  oauth_clients = [oci_identity_domains_app.k8s_exchange.name]

  # The RPST represents the workload itself, not a service user. `subject_type`
  # must be Resource and the propagated claims need the `ext_` prefix (the API
  # rejects anything else with `invalidAttributes`); at most three are allowed.
  allow_impersonation    = true
  subject_type           = "Resource"
  impersonating_resource = "k8sworkload"
  claim_propagations     = ["ext_sub", "ext_iss"]
}

output "k8s_exchange_client_id" {
  description = "Client id of the in-cluster token-exchange app"
  value       = oci_identity_domains_app.k8s_exchange.name
}

output "k8s_exchange_client_secret" {
  description = "Client secret of the in-cluster token-exchange app. Not pushed anywhere yet: the sidecar's Secret in tnoff/terraform apps/ is a later change."
  value       = oci_identity_domains_app.k8s_exchange.client_secret
  sensitive   = true
}
