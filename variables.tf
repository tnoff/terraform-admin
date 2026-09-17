# ==============================================================================
# Required Variables
# ==============================================================================

variable "oci_tenancy_ocid" {
  description = "OCID of the tenancy (all resources created in root compartment)"
  type        = string
}

# ==============================================================================
# Optional Variables - Provider Configuration
# ==============================================================================

variable "oci_region" {
  description = "OCI region"
  type        = string
  default     = "us-ashburn-1"
}

variable "config_file_profile" {
  description = "Profile name in ~/.oci/config file"
  type        = string
  default     = "DEFAULT"
}

# ==============================================================================
# Optional Variables - Storage Configuration
# ==============================================================================

variable "state_bucket_prefix" {
  description = "Prefix for state bucket names"
  type        = string
  default     = "terraform-state"
}

variable "workspaces" {
  description = "List of workspace names to create state buckets for (admin state stays local)"
  type        = list(string)
  # Order mirrors the apply layering (oci/infra foundation -> bootstrap ->
  # apps/dns). `bootstrap` is the operator-run cluster-foundation stack
  # (terraform/bootstrap) — its backend is terraform-state-bootstrap, and
  # this list also drives the objectstorage KMS-use policy below.
  default = ["discord", "infra", "oci", "oci-alarms", "bootstrap", "apps", "dns"]
}

variable "vault_name" {
  description = "Name prefix for the vault and KMS key"
  type        = string
  default     = "terraform-state"
}

# ==============================================================================
# Optional Variables - Terraform Admin User
# ==============================================================================

variable "terraform_admin_user_name" {
  description = "Name of the Terraform admin user for infrastructure management"
  type        = string
  default     = "terraform-admin"
}

variable "terraform_admin_group_name" {
  description = "Name of the Terraform admin group"
  type        = string
  default     = "terraform-administrators"
}

variable "terraform_admin_private_key_path" {
  description = "Path where the Terraform admin private key will be saved"
  type        = string
  default     = "generated-output/terraform_admin_private_key.pem"
}

# ==============================================================================
# Optional Variables - MCP Readonly User
# ==============================================================================

variable "mcp_readonly_user_name" {
  description = "Name of the tenancy-wide read-only user backing the local OCI MCP server"
  type        = string
  default     = "mcp-readonly-bot"
}

variable "mcp_readonly_group_name" {
  description = "Name of the tenancy-wide read-only group backing the local OCI MCP server"
  type        = string
  default     = "mcp-readonly-bot"
}

variable "mcp_readonly_private_key_path" {
  description = "Path where the MCP read-only user's API key PEM will be written"
  type        = string
  default     = "generated-output/mcp_readonly_api_key.pem"
}

# ==============================================================================
# External Secrets — admin/ holds these and pushes them to the `terraform`
# GitLab project's CI/CD variables (via the gitlab/repo module call below).
# Manually rotated by editing this stack's tfvars (or env vars) and re-applying.
# ==============================================================================

variable "cloudflare_api_token" {
  description = "Cloudflare account API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account identifier (not secret)"
  type        = string
}

variable "discord_token" {
  description = "Discord bot token"
  type        = string
  sensitive   = true
}

# ==============================================================================
# tnoff-flux GitHub App -- Flux's read credential for docker-apps.
#
# Separate from tnoff-ci on purpose. Flux needs Contents:read on ONE repo and
# holds its credential in-cluster forever; tnoff-ci carries Contents AND
# Workflows WRITE across the whole fleet, so reusing it would turn an
# in-cluster Secret compromise into fleet-wide write access.
#
# Flux authenticates as the App natively (FluxInstance sync.provider = "github",
# supported since Flux 2.5 and verified against the installed 2.9.1 CRD enum).
# source-controller mints and refreshes its own hourly installation tokens from
# the App private key, so unlike a fine-grained PAT there is nothing that
# expires and stops reconciliation silently.
#
# All three are consumed by the operator-run bootstrap stack via the local
# .envrc ONLY -- deliberately absent from terraform_ci_vars, the same treatment
# the sealed-secrets controller key gets. Nothing in CI needs them.
# ==============================================================================
# tnoff-terraform GitHub App -- the identity terraform/infra manages GitHub with.
#
# Replaces github_token, which is the human admin PAT. That token carries the
# whole account: every org membership, every repo the human can see, and it
# authenticates AS the human in audit logs. The App is scoped to the repos it
# is installed on, mints 1-hour tokens, is revocable in one click, and appears
# as itself.
#
# Separate from tnoff-ci and tnoff-flux on purpose, and it is the most
# privileged of the three -- Administration:write is what creates repositories
# and manages rulesets. tnoff-ci pushes commits and would not survive being
# given repo-admin; tnoff-flux reads one repo. Three Apps, three blast radii.
#
# Known limitation, unresolved at the time of writing: it is not documented
# whether an installation token can create a repository on a PERSONAL account
# (POST /user/repos). All 23 repos already exist, so this only matters when
# adding a new one -- and it fails loudly with an obvious workaround (create by
# hand, adopt with `import`) rather than silently.
variable "terraform_app_id" {
  type        = number
  description = "App ID of the tnoff-terraform GitHub App. Not a secret. From https://github.com/settings/apps/tnoff-terraform."
}

variable "terraform_app_installation_id" {
  type        = number
  description = "Installation ID of the tnoff-terraform App on this account -- the trailing number in https://github.com/settings/installations/<id>. Not a secret."
}

variable "terraform_app_private_key_b64" {
  type        = string
  sensitive   = true
  description = "Base64 of the tnoff-terraform App private key PEM, single line. Produce with `base64 -w0 tnoff-terraform.*.private-key.pem`. Set in admin/terraform.tfvars (gitignored); terraform/infra base64decodes it for the provider's app_auth block."
}

variable "flux_app_id" {
  type        = number
  description = "App ID of the tnoff-flux GitHub App. Not a secret. From https://github.com/settings/apps/tnoff-flux."
}

variable "flux_app_installation_id" {
  type        = number
  description = "Installation ID of the tnoff-flux App on tnoff/docker-apps -- the trailing number in https://github.com/settings/installations/<id>. Not a secret. Flux accepts githubAppInstallationOwner instead, but the ID has been supported since 2.5 and the owner form is newer, so the ID is the safer pin."
}

variable "flux_app_private_key_b64" {
  type        = string
  sensitive   = true
  description = "Base64 of the tnoff-flux App private key PEM, single line. Base64 for the same reason ci_app_private_key_b64 is: a multi-line PEM does not survive a shell round-trip cleanly. Produce with `base64 -w0 tnoff-flux.*.private-key.pem`. Set in admin/terraform.tfvars (gitignored); bootstrap base64decodes it into the Secret."
}

variable "backstage_app_id" {
  type        = number
  description = "App ID of the tnoff-backstage GitHub App. Not a secret. From https://github.com/settings/apps/tnoff-backstage."
}

variable "backstage_app_client_id" {
  type        = string
  description = "Client ID of the tnoff-backstage GitHub App (Iv23li... form). Not a secret, and shown on the App settings page without generating anything. Backstage requires the key to be PRESENT (readGithubIntegrationConfig uses getString, not getOptionalString) but never uses it: SingleInstanceGithubCredentialsProvider builds its auth config from appId + privateKey alone. Supplied so config parsing succeeds."
}

variable "backstage_app_private_key_b64" {
  type        = string
  sensitive   = true
  description = "Base64 of the tnoff-backstage App private key PEM, single line. Base64 for the same reason ci_app_private_key_b64 is: a multi-line PEM does not survive a shell round-trip cleanly. Produce with `base64 -w0 tnoff-backstage.*.private-key.pem`. Set in admin/terraform.tfvars (gitignored); apps/ base64decodes it into the Secret the pod mounts."
}

variable "ci_app_id" {
  type        = number
  description = "App ID of the tnoff-ci GitHub App. Exported so terraform/infra can name it as a ruleset bypass actor (actor_type Integration) and mint installation tokens in CI, replacing the human admin PAT that assemble-changelog needs to push to a protected default branch. Not a secret."
}

variable "ci_app_client_id" {
  type        = string
  description = "Client ID of the tnoff-ci GitHub App (Iv23li... form). Distinct from ci_app_id: actions/create-github-app-token deprecated its `app-id` input in favour of `client-id`, while the ruleset bypass actor still keys on the numeric App ID. Both are needed. Not a secret."
}

variable "ci_app_private_key_b64" {
  type        = string
  description = "Base64 of the tnoff-ci GitHub App private key PEM, single line. Base64 rather than the raw PEM for the same reason OCI_API_KEY_B64 is: GitLab can only mask a single-line value, so a multi-line PEM would have to travel through CI unmasked. Produce with `base64 -w0 tnoff-ci.private-key.pem`; terraform/infra base64decodes it when writing the Actions secret."
  sensitive   = true
}

variable "gitlab_api_key" {
  description = "GitLab personal access token for admin user"
  type        = string
  sensitive   = true
}

variable "gitlab_ci_api_key" {
  description = "GitLab access token for the tnoff-ci service account (formerly the tnoff-robot user's PAT, and formerly named gitlab_bot_api_key)"
  type        = string
  sensitive   = true
}

variable "gitlab_ci_service_account_id" {
  description = "Numeric service_account_id (as a string) of the tnoff-ci GitLab group service account, created manually via the GitLab UI. Not a secret."
  type        = string
}

variable "secret_age_tracker_gitlab_token" {
  description = "GitLab personal access token consumed by the secret-age-tracker CronJob (read_api scope). Used to blame docker-apps SealedSecret YAMLs and list PAT expiries. Folded into the oke-security-scanner image per docs/projects/secret-age-tracker.md."
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for OKE worker nodes"
  type        = string
}

variable "alarm_email" {
  description = "Email address for OCI alarm notifications"
  type        = string
}

# ==============================================================================
# Sealed-secrets controller key — the single backed-up controller key
# (docs/projects/sealed-secrets-key-bootstrap.md). Held in admin LOCAL state
# ONLY and surfaced to the operator-run `bootstrap` stack via TF_VAR_* in the
# generated .envrc — deliberately NOT pushed to the `terraform` GitLab CI
# variables (the master key must never live in CI). Values are the base64
# strings straight from the live Secret's .data (single-line, env-var-safe,
# exactly like OCI_API_KEY_B64); bootstrap base64-decodes them into the
# kubernetes.io/tls Secret the controller adopts on a green-field start.
# ==============================================================================

variable "sealed_secrets_tls_crt_b64" {
  description = "Base64 (as stored in the Secret .data) of the sealed-secrets controller key certificate (tls.crt). Source: kubectl -n sealed-secrets get secret sealed-secrets-keyptkzt -o jsonpath='{.data.tls\\.crt}'"
  type        = string
  sensitive   = true
}

variable "sealed_secrets_tls_key_b64" {
  description = "Base64 (as stored in the Secret .data) of the sealed-secrets controller private key (tls.key). Source: kubectl -n sealed-secrets get secret sealed-secrets-keyptkzt -o jsonpath='{.data.tls\\.key}'"
  type        = string
  sensitive   = true
}

