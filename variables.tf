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

variable "github_token" {
  description = "GitHub personal access token (admin)"
  type        = string
  sensitive   = true
}

variable "bot_github_token" {
  description = "GitHub personal access token used by Renovate"
  type        = string
  sensitive   = true
}

variable "github_actions_token" {
  description = <<-EOT
    GitHub PAT for @tnoff, used by GitHub Actions on repos that have flipped
    to GitHub-canonical. Needs `repo` scope.

    Deliberately separate from github_token, which is the push-mirror
    credential and is retired repo-by-repo as the migration proceeds.
    Deliberately NOT the same identity as bot_github_token: this is what
    renovate-auto-approve approves Renovate's own PRs with, and GitHub
    refuses to let a PR author approve their own PR.
  EOT
  type        = string
  sensitive   = true
}

variable "ci_app_id" {
  type        = number
  description = "App ID of the tnoff-ci GitHub App. Exported so terraform/infra can name it as a ruleset bypass actor (actor_type Integration) and mint installation tokens in CI, replacing the human admin PAT that assemble-changelog needs to push to a protected default branch. Not a secret."
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

variable "gitlab_bot_api_key" {
  description = "GitLab personal access token for bot user"
  type        = string
  sensitive   = true
}

variable "secret_age_tracker_gitlab_token" {
  description = "GitLab personal access token consumed by the secret-age-tracker CronJob (read_api scope). Used to blame docker-apps SealedSecret YAMLs and list PAT expiries. Folded into the oke-security-scanner image per docs/projects/secret-age-tracker.md."
  type        = string
  sensitive   = true
}

variable "gcpe_gitlab_token" {
  description = "GitLab personal access token (read_api scope) for gitlab-ci-pipelines-exporter (GCPE). Rendered into the gcpe-gitlab-token k8s Secret in the monitoring ns by the apps/ stack. Manual PAT (gitlab.com Free tier can't mint group access tokens) — same shape as secret_age_tracker_gitlab_token. See docs/projects/gitlab-ci-metrics.md."
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

