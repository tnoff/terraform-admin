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
  default     = ["discord", "infra", "oci", "apps", "dns"]
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

variable "terraform_admin_public_key_path" {
  description = "Path where the Terraform admin public key will be saved"
  type        = string
  default     = "generated-output/terraform_admin_public_key.pem"
}

# ==============================================================================
# External Secrets — admin/ holds these for `infra/` to push into the
# `terraform` GitLab project's CI/CD variables. Manually rotated by editing
# this stack's tfvars (or env vars) and re-applying admin/ + infra/.
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

variable "ssh_public_key" {
  description = "SSH public key for OKE worker nodes"
  type        = string
}

variable "alarm_email" {
  description = "Email address for OCI alarm notifications"
  type        = string
}

variable "admin_secrets_bundle_path" {
  description = "Path where the admin secrets bundle JSON is written"
  type        = string
  default     = "generated-output/admin_secrets.json"
}

