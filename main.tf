# ==============================================================================
# Data Sources
# ==============================================================================

data "oci_identity_tenancy" "current" {
  tenancy_id = var.oci_tenancy_ocid
}

data "oci_objectstorage_namespace" "this" {
  compartment_id = var.oci_tenancy_ocid
}

# ==============================================================================
# KMS Vault and Encryption Key
# ==============================================================================

module "terraform_state_vault" {
  source = "git::https://gitlab.com/tnoff-projects/terraform-modules.git//oci/secret-vault?ref=0611b7d8e4409a930c6b9dfa021076784249b520"

  compartment_ocid    = var.oci_tenancy_ocid
  display_name        = var.vault_name
  key_shape_length    = 32
  key_shape_algorithm = "AES"
  freeform_tags = {
    "Purpose"   = "terraform-state"
    "ManagedBy" = "terraform"
  }
}

# ==============================================================================
# Object Storage Buckets (one per workspace)
# ==============================================================================

module "terraform_state_buckets" {
  source                          = "git::https://gitlab.com/tnoff-projects/terraform-modules.git//oci/object-storage-bucket?ref=0611b7d8e4409a930c6b9dfa021076784249b520"
  for_each                        = toset(var.workspaces)
  compartment_ocid                = var.oci_tenancy_ocid
  kms_key_ocid                    = module.terraform_state_vault.kms_key.id
  namespace                       = data.oci_objectstorage_namespace.this.namespace
  display_name                    = "${var.state_bucket_prefix}-${each.key}"
  versioning_enabled              = true
  archive_after                   = 0
  delete_after                    = 0
  abort_incomplete_uploads_after  = 7
  archive_previous_versions_after = 30
  delete_previous_versions_after  = 90
  freeform_tags = {
    "Purpose"   = "terraform-state"
    "ManagedBy" = "terraform"
    "Workspace" = each.key
  }
}

# ==============================================================================
# IAM Resources - Terraform Admin User
# ==============================================================================

# Generate RSA key pair for Terraform admin user
resource "tls_private_key" "terraform_admin" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# IAM User for managing infrastructure via Terraform
resource "oci_identity_user" "terraform_admin" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Administrative user for managing infrastructure with Terraform"
  name           = var.terraform_admin_user_name

  freeform_tags = {
    "Purpose"   = "terraform-infrastructure-management"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

# API Key for the admin user (for OCI provider)
resource "oci_identity_api_key" "terraform_admin" {
  user_id   = oci_identity_user.terraform_admin.id
  key_value = tls_private_key.terraform_admin.public_key_pem
}

# PEM written to disk because the workload repo's OCI provider auths via
# OCI_PRIVATE_KEY_PATH (env var → file path) — the .envrc below points
# at this exact file. Provider 8.x can also take the literal PEM via
# OCI_PRIVATE_KEY, but multi-line env vars are flaky across shells; the
# file path is single-line and bulletproof.
resource "local_sensitive_file" "terraform_admin_private_key" {
  content         = tls_private_key.terraform_admin.private_key_pem
  filename        = var.terraform_admin_private_key_path
  file_permission = "0600"
}

# Admin group for infrastructure management
resource "oci_identity_group" "terraform_admin" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Administrators group for Terraform infrastructure management"
  name           = var.terraform_admin_group_name

  freeform_tags = {
    "Purpose"   = "terraform-infrastructure-management"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

# Add admin user to admin group
resource "oci_identity_user_group_membership" "terraform_admin" {
  group_id = oci_identity_group.terraform_admin.id
  user_id  = oci_identity_user.terraform_admin.id
}


# ==============================================================================
# IAM Policies
# ==============================================================================

# Policy for Terraform admin group - full infrastructure management
resource "oci_identity_policy" "terraform_admin" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Administrative policy for Terraform infrastructure management"
  name           = "terraform-admin-policy"

  statements = [
    "Allow group ${oci_identity_group.terraform_admin.name} to manage all-resources in compartment id ${var.oci_tenancy_ocid}",
  ]

  freeform_tags = {
    "Purpose"   = "terraform-infrastructure-management"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

# Policy to allow Object Storage service to use KMS keys for bucket encryption
resource "oci_identity_policy" "admin_kms_object_storage" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Allow Object Storage service to use KMS keys for terraform state buckets"
  name           = "admin-kms-object-storage-policy"

  statements = concat(
    [
      "Allow service objectstorage-${var.oci_region} to use keys in tenancy where target.key.id = '${module.terraform_state_vault.kms_key.id}'",
    ],
    [
      for workspace in var.workspaces :
      "Allow service objectstorage-${var.oci_region} to manage object-family in tenancy where target.bucket.name = '${var.state_bucket_prefix}-${workspace}'"
    ]
  )

  freeform_tags = {
    "Purpose"   = "admin-kms-object-storage-access"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

# ==============================================================================
# Values pushed to the `terraform` GitLab project as CI/CD variables, AND
# exported from .envrc for local dev. PEM goes via OCI_API_KEY_B64
# (base64-encoded, single-line) — multi-line PEMs through env vars are
# unreliable across shells, so CI's before_script decodes it to disk and
# uses OCI_PRIVATE_KEY_PATH instead.
# ==============================================================================

locals {
  admin_secrets_bundle = {
    # OCI auth — short single-line values native env vars OK
    OCI_TENANCY_OCID = var.oci_tenancy_ocid
    OCI_USER_OCID    = oci_identity_user.terraform_admin.id
    OCI_FINGERPRINT  = oci_identity_api_key.terraform_admin.fingerprint

    # PEM as base64. CI before_script decodes it to a file at a known
    # path and exports OCI_PRIVATE_KEY_PATH + TF_VAR_oci_private_key_path.
    OCI_API_KEY_B64 = base64encode(tls_private_key.terraform_admin.private_key_pem)

    # Same OCI auth values exposed as TF input variables so infra/ can
    # read them at terraform-eval time (and push them back as CI variables
    # on subsequent runs), and so oci/ can use var.oci_tenancy_ocid for
    # data sources. Duplication vs OCI_* is intentional — different
    # consumers, same value.
    TF_VAR_oci_tenancy_ocid = var.oci_tenancy_ocid
    TF_VAR_oci_user_ocid    = oci_identity_user.terraform_admin.id
    TF_VAR_oci_fingerprint  = oci_identity_api_key.terraform_admin.fingerprint
    TF_VAR_oci_api_key_b64  = base64encode(tls_private_key.terraform_admin.private_key_pem)

    TF_VAR_cloudflare_api_token  = var.cloudflare_api_token
    TF_VAR_cloudflare_account_id = var.cloudflare_account_id
    TF_VAR_discord_token         = var.discord_token
    TF_VAR_github_token          = var.github_token
    TF_VAR_gitlab_api_key        = var.gitlab_api_key
    TF_VAR_gitlab_bot_api_key    = var.gitlab_bot_api_key
    TF_VAR_mcp_gitlab_token      = var.mcp_gitlab_token
    TF_VAR_ssh_public_key        = var.ssh_public_key
    TF_VAR_alarm_email           = var.alarm_email

    GITHUB_BOT_TOKEN = var.bot_github_token
  }
}

# Local-dev convenience: drop a .envrc next to the secrets bundle that
# exports every env var terragrunt + the OCI provider + the workload-repo
# stacks need. Source via direnv (`direnv allow`) or
# `set -a; . generated-output/.envrc; set +a`.
#
# Built via list-join with explicit "\n" (LF) literals so the output is
# LF-regardless-of-source-line-endings — heredoc + template directives
# preserve admin/main.tf's line endings, which produced CRLF and broke
# the get_env() substitution in root.hcl.
locals {
  envrc_lines = concat(
    ["# Auto-generated by admin/ — do not edit. Source via direnv or `set -a; . .envrc; set +a`."],
    [
      for k, v in local.admin_secrets_bundle :
      "export ${k}=${jsonencode(v)}"
    ],
    # PEM path differs between local and CI, so it's set here (local) and
    # in CI's .gitlab-ci.yml before_script (CI). Not in admin_secrets_bundle.
    [
      "export OCI_PRIVATE_KEY_PATH=${jsonencode(abspath(var.terraform_admin_private_key_path))}",
      "export TF_VAR_oci_private_key_path=${jsonencode(abspath(var.terraform_admin_private_key_path))}",
    ],
  )
}

resource "local_sensitive_file" "envrc" {
  filename        = "generated-output/.envrc"
  file_permission = "0600"
  content         = "${join("\n", local.envrc_lines)}\n"
}

# ==============================================================================
# GitLab project hosting this terraform code + its CI/CD variables.
#
# Lives in admin/ (not infra/) because:
#   1. admin already owns the secrets that populate every CI variable —
#      having infra/ relay them just adds a bootstrap-window hop.
#   2. admin already creates the OCI side of the bootstrap (state buckets,
#      IAM, KMS); creating the GitLab project that uses them belongs in
#      the same layer.
#   3. admin/ is the *only* stack that interacts with the `terraform`
#      GitLab project. infra/ keeps everything else (eastbay, discord-bot,
#      etc.) — those legitimately depend on oci/'s outputs and live
#      downstream.
# ==============================================================================

data "gitlab_group" "personal" {
  full_path = "tnoff-projects"
}

locals {
  # Map of GitLab CI variables → values, all sourced from admin's own
  # inputs / outputs.
  terraform_ci_vars = {
    OCI_TENANCY_OCID = var.oci_tenancy_ocid
    OCI_USER_OCID    = oci_identity_user.terraform_admin.id
    OCI_FINGERPRINT  = oci_identity_api_key.terraform_admin.fingerprint
    OCI_API_KEY_B64  = base64encode(tls_private_key.terraform_admin.private_key_pem)

    TF_VAR_oci_tenancy_ocid = var.oci_tenancy_ocid
    TF_VAR_oci_user_ocid    = oci_identity_user.terraform_admin.id
    TF_VAR_oci_fingerprint  = oci_identity_api_key.terraform_admin.fingerprint
    TF_VAR_oci_api_key_b64  = base64encode(tls_private_key.terraform_admin.private_key_pem)

    TF_VAR_cloudflare_api_token  = var.cloudflare_api_token
    TF_VAR_cloudflare_account_id = var.cloudflare_account_id
    TF_VAR_discord_token         = var.discord_token
    TF_VAR_github_token          = var.github_token
    TF_VAR_gitlab_api_key        = var.gitlab_api_key
    TF_VAR_gitlab_bot_api_key    = var.gitlab_bot_api_key
    TF_VAR_mcp_gitlab_token      = var.mcp_gitlab_token
    TF_VAR_ssh_public_key        = var.ssh_public_key
    TF_VAR_alarm_email           = var.alarm_email

    GITHUB_BOT_TOKEN = var.bot_github_token
  }

  # GitLab masking requires single-line, ≥8 chars, no '@'. These can't be
  # masked; explicit allowlist so the rest stay masked by default.
  terraform_ci_vars_unmasked = [
    "TF_VAR_alarm_email",
    "TF_VAR_ssh_public_key",
    "TF_VAR_cloudflare_account_id",
  ]

  terraform_weekly_schedule = {
    weekly = {
      description = "Weekly Workflow Run"
      ref         = "refs/heads/main"
      cron        = "0 0 * * *" # Once a week on sunday
      active      = true
    }
  }
}

module "terraform_gitlab" {
  source           = "git::https://gitlab.com/tnoff-projects/terraform-modules.git//gitlab/repo?ref=b7b699cd886c0d29c8aac66337381d6a8939495a"
  name             = "terraform"
  namespace_id     = data.gitlab_group.personal.id
  visibility_level = "private"

  schedules = local.terraform_weekly_schedule

  pipeline_variables = {
    for key, value in local.terraform_ci_vars :
    key => {
      value  = value
      masked = !contains(local.terraform_ci_vars_unmasked, key)
    }
  }
}

# ==============================================================================
# State migration: lift orphan root-level resources into the
# terraform_state_buckets module they conceptually belong to. The infra bucket
# and all four lifecycle policies were left at root from a prior partial
# refactor; these moves preserve cloud resources without recreating them.
# ==============================================================================

moved {
  from = oci_objectstorage_bucket.terraform_state["infra"]
  to   = module.terraform_state_buckets["infra"].oci_objectstorage_bucket.this
}

moved {
  from = oci_objectstorage_object_lifecycle_policy.terraform_state["apps"]
  to   = module.terraform_state_buckets["apps"].oci_objectstorage_object_lifecycle_policy.this
}

moved {
  from = oci_objectstorage_object_lifecycle_policy.terraform_state["discord"]
  to   = module.terraform_state_buckets["discord"].oci_objectstorage_object_lifecycle_policy.this
}

moved {
  from = oci_objectstorage_object_lifecycle_policy.terraform_state["infra"]
  to   = module.terraform_state_buckets["infra"].oci_objectstorage_object_lifecycle_policy.this
}

moved {
  from = oci_objectstorage_object_lifecycle_policy.terraform_state["oci"]
  to   = module.terraform_state_buckets["oci"].oci_objectstorage_object_lifecycle_policy.this
}
