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
  source = "git::https://gitlab.com/tnoff-projects/terraform-modules.git//oci/secret-vault?ref=43788ab89edaf512387cb1548ce8377e1054850a"

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
  source                          = "git::https://gitlab.com/tnoff-projects/terraform-modules.git//oci/object-storage-bucket?ref=43788ab89edaf512387cb1548ce8377e1054850a"
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
# IAM Resources - MCP Readonly User
#
# Tenancy-wide read-only user backing the local OCI MCP server. Operator-facing
# (not a workload component), so it lives alongside terraform_admin rather than
# in the oci/ workload stack. PEM + ~/.oci/config fragment are written to
# generated-output/ for the operator to paste into ~/.oci/config.
# ==============================================================================

resource "tls_private_key" "mcp_readonly" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "oci_identity_user" "mcp_readonly" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Tenancy-wide read-only user backing the local OCI MCP server"
  name           = var.mcp_readonly_user_name

  freeform_tags = {
    "Purpose"   = "mcp-readonly"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

resource "oci_identity_api_key" "mcp_readonly" {
  user_id   = oci_identity_user.mcp_readonly.id
  key_value = tls_private_key.mcp_readonly.public_key_pem
}

resource "local_sensitive_file" "mcp_readonly_private_key" {
  content         = tls_private_key.mcp_readonly.private_key_pem
  filename        = var.mcp_readonly_private_key_path
  file_permission = "0600"
}

resource "oci_identity_group" "mcp_readonly" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Tenancy-wide read-only group backing the local OCI MCP server"
  name           = var.mcp_readonly_group_name

  freeform_tags = {
    "Purpose"   = "mcp-readonly"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

resource "oci_identity_user_group_membership" "mcp_readonly" {
  group_id = oci_identity_group.mcp_readonly.id
  user_id  = oci_identity_user.mcp_readonly.id
}

# Pre-formatted ~/.oci/config fragment. Named profile (MCP_READONLY) so it
# composes with any existing DEFAULT block instead of overwriting it.
resource "local_sensitive_file" "mcp_readonly_oci_config" {
  filename        = "generated-output/mcp_readonly_oci_config"
  file_permission = "0600"
  content         = <<-EOT
  [MCP_READONLY]
  user=${oci_identity_user.mcp_readonly.id}
  fingerprint=${oci_identity_api_key.mcp_readonly.fingerprint}
  tenancy=${var.oci_tenancy_ocid}
  region=${var.oci_region}
  key_file=${abspath(var.mcp_readonly_private_key_path)}
  EOT
}

# ==============================================================================
# IAM Policies
# ==============================================================================

# Policy for MCP readonly group - tenancy-wide read of all resources
resource "oci_identity_policy" "mcp_readonly" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Tenancy-wide read-only policy backing the local OCI MCP server"
  name           = "mcp-readonly-policy"

  statements = [
    "Allow group ${oci_identity_group.mcp_readonly.name} to read all-resources in tenancy",
  ]

  freeform_tags = {
    "Purpose"   = "mcp-readonly"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

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
    TF_VAR_ssh_public_key        = var.ssh_public_key
    TF_VAR_alarm_email           = var.alarm_email

    # Sealed-secrets controller key (base64, single-line). Local .envrc ONLY —
    # deliberately absent from terraform_ci_vars below so the master key never
    # lands in the `terraform` GitLab CI variables. Consumed by the operator-run
    # bootstrap stack to seed the controller key on a green-field start. See
    # docs/projects/sealed-secrets-key-bootstrap.md.
    TF_VAR_sealed_secrets_tls_crt_b64 = var.sealed_secrets_tls_crt_b64
    TF_VAR_sealed_secrets_tls_key_b64 = var.sealed_secrets_tls_key_b64

    # Consumed by the apps/ stack to materialize the
    # `secret-age-tracker-gitlab-token` k8s Secret in the security-scanner
    # ns. Folded into the oke-security-scanner image per
    # docs/projects/secret-age-tracker.md.
    TF_VAR_secret_age_tracker_gitlab_token = var.secret_age_tracker_gitlab_token

    # Consumed by the apps/ stack to materialize the `gcpe-gitlab-token` k8s
    # Secret in the monitoring ns (gitlab-ci-pipelines-exporter). Same shape as
    # secret_age_tracker_gitlab_token. See docs/projects/gitlab-ci-metrics.md.
    TF_VAR_gcpe_gitlab_token = var.gcpe_gitlab_token

    # Auto-captured rotation timestamps — see rotation-tracking.tf.
    # Each `time_static.<var>_rotated_at.rfc3339` is fresh when the
    # underlying tfvar value's sha256 changes, and pinned otherwise.
    # The apps/ stack reads these and writes the
    # `layer-1-rotation-ledger` ConfigMap from them.
    TF_VAR_discord_token_rotated_at                   = time_static.discord_token_rotated_at.rfc3339
    TF_VAR_cloudflare_api_token_rotated_at            = time_static.cloudflare_api_token_rotated_at.rfc3339
    TF_VAR_github_token_rotated_at                    = time_static.github_token_rotated_at.rfc3339
    TF_VAR_bot_github_token_rotated_at                = time_static.bot_github_token_rotated_at.rfc3339
    TF_VAR_gitlab_api_key_rotated_at                  = time_static.gitlab_api_key_rotated_at.rfc3339
    TF_VAR_gitlab_bot_api_key_rotated_at              = time_static.gitlab_bot_api_key_rotated_at.rfc3339
    TF_VAR_ssh_public_key_rotated_at                  = time_static.ssh_public_key_rotated_at.rfc3339
    TF_VAR_secret_age_tracker_gitlab_token_rotated_at = time_static.secret_age_tracker_gitlab_token_rotated_at.rfc3339
    TF_VAR_gcpe_gitlab_token_rotated_at               = time_static.gcpe_gitlab_token_rotated_at.rfc3339

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
    TF_VAR_ssh_public_key        = var.ssh_public_key
    TF_VAR_alarm_email           = var.alarm_email

    # See admin_secrets_bundle for the rationale on the rotated_at
    # values — same source, different consumer (CI vs local .envrc).
    TF_VAR_secret_age_tracker_gitlab_token = var.secret_age_tracker_gitlab_token
    TF_VAR_gcpe_gitlab_token               = var.gcpe_gitlab_token

    TF_VAR_discord_token_rotated_at                   = time_static.discord_token_rotated_at.rfc3339
    TF_VAR_cloudflare_api_token_rotated_at            = time_static.cloudflare_api_token_rotated_at.rfc3339
    TF_VAR_github_token_rotated_at                    = time_static.github_token_rotated_at.rfc3339
    TF_VAR_bot_github_token_rotated_at                = time_static.bot_github_token_rotated_at.rfc3339
    TF_VAR_gitlab_api_key_rotated_at                  = time_static.gitlab_api_key_rotated_at.rfc3339
    TF_VAR_gitlab_bot_api_key_rotated_at              = time_static.gitlab_bot_api_key_rotated_at.rfc3339
    TF_VAR_ssh_public_key_rotated_at                  = time_static.ssh_public_key_rotated_at.rfc3339
    TF_VAR_secret_age_tracker_gitlab_token_rotated_at = time_static.secret_age_tracker_gitlab_token_rotated_at.rfc3339
    TF_VAR_gcpe_gitlab_token_rotated_at               = time_static.gcpe_gitlab_token_rotated_at.rfc3339

    GITHUB_BOT_TOKEN = var.bot_github_token
  }

  # GitLab masking requires single-line, ≥8 chars, no '@'. These can't be
  # masked; explicit allowlist so the rest stay masked by default.
  terraform_ci_vars_unmasked = [
    "TF_VAR_alarm_email",
    "TF_VAR_ssh_public_key",
    "TF_VAR_cloudflare_account_id",
    # rotated_at timestamps are RFC3339 strings containing `:` which
    # GitLab masking rejects. Contents are non-secret apply timestamps,
    # safe to expose.
    "TF_VAR_discord_token_rotated_at",
    "TF_VAR_cloudflare_api_token_rotated_at",
    "TF_VAR_github_token_rotated_at",
    "TF_VAR_bot_github_token_rotated_at",
    "TF_VAR_gitlab_api_key_rotated_at",
    "TF_VAR_gitlab_bot_api_key_rotated_at",
    "TF_VAR_ssh_public_key_rotated_at",
    "TF_VAR_secret_age_tracker_gitlab_token_rotated_at",
    "TF_VAR_gcpe_gitlab_token_rotated_at",
  ]

  terraform_weekly_schedule = {
    weekly = {
      description = "Weekly Workflow Run"
      ref         = "refs/heads/main"
      cron        = "0 0 * * 0" # Once a week on sunday
      active      = true
    }
  }
}

module "terraform_gitlab" {
  source           = "git::https://gitlab.com/tnoff-projects/terraform-modules.git//gitlab/repo?ref=43788ab89edaf512387cb1548ce8377e1054850a"
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
