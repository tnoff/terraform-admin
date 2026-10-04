# ==============================================================================
# GitHub OIDC -> OCI identity propagation: SPIKE (tnoff/terraform#135)
#
# Lets a GitHub Actions job exchange its signed OIDC token for a one-hour OCI
# session token (UPST) instead of holding an API key. Additive and self-
# contained: nothing else in this stack references these resources, and the
# whole spike is removed by deleting this file (go/no-go in the issue).
#
# Shape:
#   exchange app   confidential app the job authenticates to /oauth2/v1/token
#                  with (client id + secret). No admin roles, per Oracle's
#                  least-privilege guidance; authorised by the trust below.
#   trust          validates GitHub's issuer + signature, then maps the token's
#                  `sub` claim to a service user by rule.
#   service user   serviceUser = true: no password, cannot hold API keys.
#   group + policy what the service user may do. For the spike: read one real
#                  state bucket, nothing else.
#
# The only identity mapped is a push to the spike branch of the terraform repo.
# tnoff/terraform has immutable subject claims on (see `gh api
# repos/tnoff/terraform/actions/oidc/customization/sub`), so `sub` carries the
# owner and repo IDs, not their names: for a push it is
# `<prefix>:ref:refs/heads/<branch>`, observed in a real run as
# `repo:tnoff@1326564/terraform@1356736164:ref:refs/heads/spike/oidc-federation`.
# A pull_request run would carry `<prefix>:pull_request`. Matching on the IDs
# also means a renamed or re-created repo of the same name cannot inherit this.
# ==============================================================================

variable "oidc_spike_sub_prefix" {
  description = "The `sub` claim prefix of the GitHub repo whose Actions tokens the spike trust accepts. With immutable subjects on it embeds owner and repo IDs; read it from `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` (sub_claim_prefix)."
  type        = string
  default     = "repo:tnoff@1326564/terraform@1356736164"
}

variable "oidc_spike_branch" {
  description = "The one branch of the repo behind oidc_spike_sub_prefix whose push runs map to the spike service user"
  type        = string
  default     = "spike/oidc-federation"
}

variable "oidc_spike_state_read_workspaces" {
  description = "State buckets the spike service user may READ (not write). Read-only on purpose: it tests whether a plan-only identity can use the OCI backend, lock included."
  type        = list(string)
  default     = ["dns"]
}

locals {
  oidc_spike_issuer = "https://token.actions.githubusercontent.com"
  oidc_spike_sub    = "${var.oidc_spike_sub_prefix}:ref:refs/heads/${var.oidc_spike_branch}"
}

# The identity domain the trust, app and service user live in. The tenancy has a
# single domain (Default); looking it up avoids hardcoding its endpoint.
data "oci_identity_domains" "default" {
  compartment_id = var.oci_tenancy_ocid
  display_name   = "Default"
}

locals {
  oidc_spike_domain_endpoint = data.oci_identity_domains.default.domains[0].url
}

resource "oci_identity_domains_user" "oidc_spike" {
  idcs_endpoint = local.oidc_spike_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User"]
  user_name     = "terraform-oidc-spike"
  description   = "Throwaway service user for the GitHub OIDC federation spike (tnoff/terraform#135)"

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }
}

resource "oci_identity_domains_group" "oidc_spike" {
  idcs_endpoint = local.oidc_spike_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = "terraform-oidc-spike"

  members {
    type  = "User"
    value = oci_identity_domains_user.oidc_spike.id
  }
}

resource "oci_identity_policy" "oidc_spike" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Throwaway policy for the GitHub OIDC federation spike: read-only on state buckets"
  name           = "terraform-oidc-spike-policy"

  statements = [
    "Allow group ${oci_identity_domains_group.oidc_spike.display_name} to read objects in tenancy where any {${join(", ", [for w in var.oidc_spike_state_read_workspaces : "target.bucket.name = '${var.state_bucket_prefix}-${w}'"])}}",
  ]

  freeform_tags = {
    "Purpose"   = "terraform-oidc-spike"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

# The app the CI job authenticates as to call the token endpoint. Its client
# secret is only useful together with a GitHub token the trust accepts.
resource "oci_identity_domains_app" "oidc_spike_exchange" {
  idcs_endpoint   = local.oidc_spike_domain_endpoint
  schemas         = ["urn:ietf:params:scim:schemas:oracle:idcs:App"]
  display_name    = "terraform-oidc-spike-exchange"
  description     = "Token-exchange client for the GitHub OIDC federation spike (tnoff/terraform#135)"
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

resource "oci_identity_domains_identity_propagation_trust" "oidc_spike" {
  idcs_endpoint = local.oidc_spike_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]
  name          = "github-actions-oidc-spike"
  description   = "Maps one GitHub Actions branch to the spike service user (tnoff/terraform#135)"
  type          = "JWT"
  active        = true

  issuer              = local.oidc_spike_issuer
  public_key_endpoint = "${local.oidc_spike_issuer}/.well-known/jwks"

  # Only the exchange app may present a GitHub token to this trust.
  oauth_clients = [oci_identity_domains_app.oidc_spike_exchange.name]

  # The UPST impersonates the service user instead of a federated human.
  allow_impersonation = true
  subject_type        = "User"

  impersonation_service_users {
    rule  = "sub eq ${local.oidc_spike_sub}"
    value = oci_identity_domains_user.oidc_spike.id
  }
}

output "oidc_spike_domain_endpoint" {
  description = "Identity domain URL the token exchange is POSTed to (<this>/oauth2/v1/token)"
  value       = local.oidc_spike_domain_endpoint
}

output "oidc_spike_exchange_client_id" {
  description = "Client id of the spike's token-exchange app"
  value       = oci_identity_domains_app.oidc_spike_exchange.name
}

output "oidc_spike_exchange_client_secret" {
  description = "Client secret of the spike's token-exchange app. Set it on tnoff/terraform by hand: terraform output -raw oidc_spike_exchange_client_secret | gh secret set OCI_EXCHANGE_CLIENT_SECRET --repo tnoff/terraform"
  value       = oci_identity_domains_app.oidc_spike_exchange.client_secret
  sensitive   = true
}

output "oidc_spike_service_user_ocid" {
  description = "OCID of the spike service user, for binding in cluster RBAC when the OKE leg of the spike runs"
  value       = oci_identity_domains_user.oidc_spike.ocid
}
