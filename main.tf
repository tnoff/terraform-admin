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
  source = "git::https://github.com/tnoff/terraform-modules.git//oci/secret-vault?ref=a853c6f188e873ec24c43e9868c99be1bf015bb9"

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
  source                          = "git::https://github.com/tnoff/terraform-modules.git//oci/object-storage-bucket?ref=a853c6f188e873ec24c43e9868c99be1bf015bb9"
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
# Values pushed to `terraform`'s GitHub Actions secrets/variables (the live
# path — see terraform_github_secrets below) and its GitLab CI variables
# (kept as a rollback path only, since .gitlab-ci.yml no longer exists in the
# mirrored content — see module.terraform_gitlab's comment), AND exported
# from .envrc for local dev. PEM goes via OCI_API_KEY_B64 (base64-encoded,
# single-line) — multi-line PEMs through env vars are unreliable across
# shells, so the terragrunt composite action's "Materialise the OCI API key"
# step (tnoff/terraform's .github/actions/terragrunt) decodes it to disk in
# CI and sets OCI_PRIVATE_KEY_PATH instead.
# ==============================================================================

locals {
  admin_secrets_bundle = {
    # OCI auth — short single-line values native env vars OK
    OCI_TENANCY_OCID = var.oci_tenancy_ocid
    OCI_USER_OCID    = oci_identity_user.terraform_admin.id
    OCI_FINGERPRINT  = oci_identity_api_key.terraform_admin.fingerprint

    # PEM as base64. The terragrunt composite action decodes it to a file
    # at a known path in CI and exports OCI_PRIVATE_KEY_PATH +
    # TF_VAR_oci_private_key_path.
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

    TF_VAR_cloudflare_api_token   = var.cloudflare_api_token
    TF_VAR_cloudflare_dns01_token = var.cloudflare_dns01_token
    TF_VAR_cloudflare_account_id  = var.cloudflare_account_id

    # discord_bot_token: back to being pushed, as of the incident on
    # 2026-09-21 -- see its description in variables.tf for why. It is now
    # consumed for real, by apps/'s kubernetes_secret_v1.discord_bot_token,
    # not just carried for no reason.
    TF_VAR_discord_bot_token        = var.discord_bot_token
    TF_VAR_discord_management_token = var.discord_management_token

    # tnoff-ci GitHub App. The identity CI pushes with, replacing the admin
    # PAT that used to be here: assemble-changelog pushes straight to a
    # protected `main`, so
    # its token must be a ruleset bypass actor, and today that means an admin
    # PAT sitting in 16 repos with a bypass over every rule. An App is
    # contents+workflows write only, issues 1-hour tokens, and -- unlike
    # GITHUB_TOKEN -- its pushes still trigger the follow-up run that cuts the tag.
    TF_VAR_ci_app_id              = var.ci_app_id
    TF_VAR_ci_app_client_id       = var.ci_app_client_id
    TF_VAR_ci_app_private_key_b64 = var.ci_app_private_key_b64

    # tnoff-terraform App -- the identity infra/ manages GitHub with, replacing
    # the human admin PAT. Needs to reach CI as well as .envrc: apply:infra runs
    # the github provider on a hosted runner.
    TF_VAR_terraform_app_id              = var.terraform_app_id
    TF_VAR_terraform_app_installation_id = var.terraform_app_installation_id
    TF_VAR_terraform_app_private_key_b64 = var.terraform_app_private_key_b64
    TF_VAR_gitlab_api_key                = var.gitlab_api_key
    TF_VAR_gitlab_ci_api_key             = var.gitlab_ci_api_key
    TF_VAR_gitlab_ci_service_account_id  = var.gitlab_ci_service_account_id
    TF_VAR_ssh_public_key                = var.ssh_public_key

    # tnoff-backstage App -- the portal's read credential for catalog discovery
    # (Contents + Metadata read, nothing else). Needs to reach CI as well as
    # .envrc, unlike the flux App above: apply:apps runs in GitHub Actions and is
    # what materialises the Secret the pod mounts.
    #
    # The private key is the ONLY secret here. GitHub App API auth is
    # appId + privateKey -> JWT -> installation token; no client secret is
    # involved. Verified in @backstage/integration rather than assumed:
    # SingleInstanceGithubCredentialsProvider sets
    # `baseAuthConfig = {appId, privateKey}` and both createAppAuth call sites
    # take exactly that, so a client secret would be read from config, carried
    # through three layers, and never reach the auth strategy. There is no such
    # tfvar -- generating a real one would mint a live OAuth credential with no
    # consumer. app-config passes a literal placeholder for the key Backstage
    # insists on parsing.
    #
    # No installation ID either, unlike tnoff-terraform and tnoff-flux.
    # @backstage/integration never reads one: the App key alone mints
    # installation tokens, and allowedInstallationOwners keys on the owner
    # LOGIN. tnoff-ci is the same shape for the same reason.
    TF_VAR_backstage_app_id              = var.backstage_app_id
    TF_VAR_backstage_app_client_id       = var.backstage_app_client_id
    TF_VAR_backstage_app_private_key_b64 = var.backstage_app_private_key_b64

    # Stamped by the sha256 trigger in rotation-tracking.tf and annotated onto
    # the backstage-github-app-credentials Secret.
    TF_VAR_backstage_app_private_key_rotated_at = time_static.backstage_app_private_key_rotated_at.rfc3339

    # Sealed-secrets controller key (base64, single-line). Local .envrc ONLY —
    # deliberately absent from terraform_ci_vars below so the master key never
    # lands in `terraform`'s CI variables, GitLab or GitHub (both are derived
    # from terraform_ci_vars). Consumed by the operator-run bootstrap stack to
    # seed the controller key on a green-field start. See
    # docs/projects/sealed-secrets-key-bootstrap.md.
    TF_VAR_sealed_secrets_tls_crt_b64 = var.sealed_secrets_tls_crt_b64
    TF_VAR_sealed_secrets_tls_key_b64 = var.sealed_secrets_tls_key_b64

    # tnoff-flux App -- Flux's read credential for docker-apps, phase 7. Local
    # .envrc ONLY, same reasoning as the sealed-secrets key above: consumed by
    # the operator-run bootstrap stack, and nothing in CI has any use for it.
    # See variables.tf for why this is a separate App from tnoff-ci.
    TF_VAR_flux_app_id              = var.flux_app_id
    TF_VAR_flux_app_installation_id = var.flux_app_installation_id
    TF_VAR_flux_app_private_key_b64 = var.flux_app_private_key_b64

    # Stamped by the sha256 trigger in rotation-tracking.tf, and annotated onto
    # the flux-system-github-app Secret so the age report covers Flux's
    # credential like every other long-lived secret.
    TF_VAR_flux_app_private_key_rotated_at = time_static.flux_app_private_key_rotated_at.rfc3339

    # Auto-captured rotation timestamps — see rotation-tracking.tf.
    # Each `time_static.<var>_rotated_at.rfc3339` is fresh when the
    # underlying tfvar value's sha256 changes, and pinned otherwise.
    # The apps/ stack reads these and writes the
    # `layer-1-rotation-ledger` ConfigMap from them.
    TF_VAR_discord_bot_token_rotated_at        = time_static.discord_bot_token_rotated_at.rfc3339
    TF_VAR_discord_management_token_rotated_at = time_static.discord_management_token_rotated_at.rfc3339
    TF_VAR_cloudflare_api_token_rotated_at     = time_static.cloudflare_api_token_rotated_at.rfc3339
    TF_VAR_cloudflare_dns01_token_rotated_at   = time_static.cloudflare_dns01_token_rotated_at.rfc3339
    TF_VAR_gitlab_api_key_rotated_at           = time_static.gitlab_api_key_rotated_at.rfc3339
    TF_VAR_gitlab_ci_api_key_rotated_at        = time_static.gitlab_ci_api_key_rotated_at.rfc3339
    TF_VAR_ssh_public_key_rotated_at           = time_static.ssh_public_key_rotated_at.rfc3339
    TF_VAR_ci_app_private_key_rotated_at       = time_static.ci_app_private_key_rotated_at.rfc3339

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
    # in the terragrunt composite action's "Materialise the OCI API key"
    # step (CI). Not in admin_secrets_bundle.
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

    TF_VAR_cloudflare_api_token   = var.cloudflare_api_token
    TF_VAR_cloudflare_dns01_token = var.cloudflare_dns01_token
    TF_VAR_cloudflare_account_id  = var.cloudflare_account_id

    # discord_bot_token: back to being pushed, as of the incident on
    # 2026-09-21 -- see its description in variables.tf for why. It is now
    # consumed for real, by apps/'s kubernetes_secret_v1.discord_bot_token,
    # not just carried for no reason.
    TF_VAR_discord_bot_token        = var.discord_bot_token
    TF_VAR_discord_management_token = var.discord_management_token

    # tnoff-ci GitHub App. The identity CI pushes with, replacing the admin
    # PAT that used to be here: assemble-changelog pushes straight to a
    # protected `main`, so
    # its token must be a ruleset bypass actor, and today that means an admin
    # PAT sitting in 16 repos with a bypass over every rule. An App is
    # contents+workflows write only, issues 1-hour tokens, and -- unlike
    # GITHUB_TOKEN -- its pushes still trigger the follow-up run that cuts the tag.
    TF_VAR_ci_app_id              = var.ci_app_id
    TF_VAR_ci_app_client_id       = var.ci_app_client_id
    TF_VAR_ci_app_private_key_b64 = var.ci_app_private_key_b64

    # tnoff-terraform App -- the identity infra/ manages GitHub with, replacing
    # the human admin PAT. Needs to reach CI as well as .envrc: apply:infra runs
    # the github provider on a hosted runner.
    TF_VAR_terraform_app_id              = var.terraform_app_id
    TF_VAR_terraform_app_installation_id = var.terraform_app_installation_id
    TF_VAR_terraform_app_private_key_b64 = var.terraform_app_private_key_b64
    TF_VAR_gitlab_api_key                = var.gitlab_api_key
    TF_VAR_gitlab_ci_api_key             = var.gitlab_ci_api_key
    TF_VAR_gitlab_ci_service_account_id  = var.gitlab_ci_service_account_id
    TF_VAR_ssh_public_key                = var.ssh_public_key

    # tnoff-backstage App -- the portal's read credential for catalog discovery
    # (Contents + Metadata read, nothing else). Needs to reach CI as well as
    # .envrc, unlike the flux App above: apply:apps runs in GitHub Actions and is
    # what materialises the Secret the pod mounts.
    #
    # The private key is the ONLY secret here. GitHub App API auth is
    # appId + privateKey -> JWT -> installation token; no client secret is
    # involved. Verified in @backstage/integration rather than assumed:
    # SingleInstanceGithubCredentialsProvider sets
    # `baseAuthConfig = {appId, privateKey}` and both createAppAuth call sites
    # take exactly that, so a client secret would be read from config, carried
    # through three layers, and never reach the auth strategy. There is no such
    # tfvar -- generating a real one would mint a live OAuth credential with no
    # consumer. app-config passes a literal placeholder for the key Backstage
    # insists on parsing.
    #
    # No installation ID either, unlike tnoff-terraform and tnoff-flux.
    # @backstage/integration never reads one: the App key alone mints
    # installation tokens, and allowedInstallationOwners keys on the owner
    # LOGIN. tnoff-ci is the same shape for the same reason.
    TF_VAR_backstage_app_id              = var.backstage_app_id
    TF_VAR_backstage_app_client_id       = var.backstage_app_client_id
    TF_VAR_backstage_app_private_key_b64 = var.backstage_app_private_key_b64

    # Stamped by the sha256 trigger in rotation-tracking.tf and annotated onto
    # the backstage-github-app-credentials Secret.
    TF_VAR_backstage_app_private_key_rotated_at = time_static.backstage_app_private_key_rotated_at.rfc3339

    # See admin_secrets_bundle for the rationale on the rotated_at
    # values — same source, different consumer (CI vs local .envrc).
    TF_VAR_discord_bot_token_rotated_at        = time_static.discord_bot_token_rotated_at.rfc3339
    TF_VAR_discord_management_token_rotated_at = time_static.discord_management_token_rotated_at.rfc3339
    TF_VAR_cloudflare_api_token_rotated_at     = time_static.cloudflare_api_token_rotated_at.rfc3339
    TF_VAR_cloudflare_dns01_token_rotated_at   = time_static.cloudflare_dns01_token_rotated_at.rfc3339
    TF_VAR_gitlab_api_key_rotated_at           = time_static.gitlab_api_key_rotated_at.rfc3339
    TF_VAR_gitlab_ci_api_key_rotated_at        = time_static.gitlab_ci_api_key_rotated_at.rfc3339
    TF_VAR_ssh_public_key_rotated_at           = time_static.ssh_public_key_rotated_at.rfc3339
    TF_VAR_ci_app_private_key_rotated_at       = time_static.ci_app_private_key_rotated_at.rfc3339

  }

  # GitLab masking requires single-line, ≥8 chars, no '@'. These can't be
  # masked; explicit allowlist so the rest stay masked by default.
  terraform_ci_vars_unmasked = [
    "TF_VAR_ssh_public_key",
    "TF_VAR_cloudflare_account_id",
    # rotated_at timestamps are RFC3339 strings containing `:` which
    # GitLab masking rejects. Contents are non-secret apply timestamps,
    # safe to expose.
    "TF_VAR_discord_bot_token_rotated_at",
    "TF_VAR_discord_management_token_rotated_at",
    "TF_VAR_cloudflare_api_token_rotated_at",
    "TF_VAR_cloudflare_dns01_token_rotated_at",
    "TF_VAR_gitlab_api_key_rotated_at",
    "TF_VAR_gitlab_ci_api_key_rotated_at",
    "TF_VAR_ssh_public_key_rotated_at",
    "TF_VAR_ci_app_private_key_rotated_at",
    # 7 characters. GitLab masking requires at least 8, so masking this is
    # rejected outright -- and an App ID is public to anyone who can see the
    # app, so there is nothing to protect.
    "TF_VAR_ci_app_id",
    "TF_VAR_terraform_app_id",
    "TF_VAR_terraform_app_installation_id",
    # Not a secret either, and masking a non-secret only makes CI logs
    # harder to read.
    "TF_VAR_ci_app_client_id",
    "TF_VAR_backstage_app_id",
    "TF_VAR_backstage_app_client_id",
    "TF_VAR_backstage_app_private_key_rotated_at",
    # A GitLab service_account_id, not a credential -- same reasoning as
    # ci_app_id above, and likely under 8 characters too.
    "TF_VAR_gitlab_ci_service_account_id",
  ]

  terraform_weekly_schedule = {
    weekly = {
      description = "Weekly Workflow Run"
      ref         = "refs/heads/main"
      # Sun 12:00, not Sun 00:00. terraform-admin's own weekly schedule also
      # fires at Sunday midnight, so the two used to start together on a ci
      # pool that scales to zero -- the cold-start pile-up behind the
      # runner_system_failure cluster in docs/projects/gitlab-ci-metrics.md.
      # infra/repos.tf staggers its own fleet by md5(name) for the same
      # reason; this project is not in that list (it is managed here), so the
      # slot is picked by hand. Sun 12:00 is empty: the nearest neighbours are
      # github-workflows at Sun 06:09 and discord-bot at Mon 04:24.
      cron = "0 12 * * 0"

      # Deactivated 2026-09-04: this project is GitHub-canonical now, and its
      # renovate + branch-cleanup run from .github/workflows/scheduled.yml on
      # the same Sunday slot.
      #
      # What this does and does not prevent, because the two are easy to
      # conflate. A SCHEDULED pipeline here runs renovate and branch-cleanup
      # only: every apply job carries `$CI_PIPELINE_SOURCE != "schedule"`, so
      # the schedule cannot apply anything. Deactivating it therefore stops
      # noise -- a second Renovate opening MRs against a frozen copy of a repo
      # nobody reads -- not an apply race.
      #
      # The apply path is a PUSH to this project's default branch, which is
      # what happened on 2026-09-04 (pipeline 2819231963, source=push, 05:55)
      # and applied two commits GitHub never had. Nothing here closes that;
      # only nobody pushing does, until the project goes read-only.
      #
      # Kept rather than deleted so the slot and its staggering rationale
      # survive; flipping this back to true is all it takes to run GitLab CI
      # again if the migration ever needs backing out.
      active = false
    }
  }
}

module "terraform_gitlab" {
  source           = "git::https://github.com/tnoff/terraform-modules.git//gitlab/repo?ref=a853c6f188e873ec24c43e9868c99be1bf015bb9"
  name             = "terraform"
  namespace_id     = data.gitlab_group.personal.id
  visibility_level = "private"

  # The module defaults to "no one", and every repo in infra/repos.tf overrides
  # it to "maintainer"; this one missed that sweep for the same reason the
  # auto_cancel setting below did -- it is managed here rather than there.
  #
  # "no one" was correct while GitLab was canonical: changes arrived by MR, and
  # allowed_to_merge (hardcoded "maintainer" in the module) is a separate gate,
  # so nothing needed direct push. The flip to GitHub inverted that. GitLab
  # `main` is now a mirror target, and github-workflows' fleet-mirror.yml
  # fast-forwards it hourly, pushing as tnoff-ci -- a group Maintainer.
  # "no one" rejects a direct push from *everyone including Owners*, so every
  # run failed with "You are not allowed to push code to protected branches"
  # and alerted #ci-alerts hourly.
  #
  # Raising this does not weaken review on the GitLab side: allowed_to_merge
  # stays "maintainer" and allow_force_push stays false, both hardcoded in the
  # module. GitHub is where the branch protection that matters now lives.
  #
  # Setting it by hand does NOT hold -- this resource is terraform-managed via
  # the module's gitlab_branch_protection.main, so the next apply here reverts
  # it. That is what happened on 2026-09-06: main was raised by hand to land a
  # force-push, and an apply the same evening put it back.
  push_access_level = "maintainer"

  # The module defaults to "enabled", which is what this project has been
  # running. Every repo in infra/repos.tf was set to "disabled" on 2026-07-25;
  # this one missed that sweep only because it is managed here rather than
  # there. With it enabled, a newer pipeline on a ref cancels an older pending
  # one -- and canceled is not failed, so `retry:` never re-runs it and the
  # Grafana gitlab-ci-job-failure alert never fires (GCPE only reads the latest
  # pipeline per ref, so it cannot see the cancelled one either). That matters
  # most here: this is the repo whose main pipelines run apply:*, so a silently
  # cancelled pipeline is an apply that never happened. See
  # docs/findings/2026-07-24-ci-bump-pipeline-autocancel-no-retry.md.
  auto_cancel_pending_pipelines = "disabled"

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
# The same credentials, on GitHub.
#
# tnoff/terraform runs its plan/apply on GitHub Actions now, so every value in
# local.terraform_ci_vars needs a second home. This is the GitHub half of
# module.terraform_gitlab's pipeline_variables -- one map, two consumers -- and
# it lives here for the reason stated above that module: admin already owns
# these values, and having infra/ relay them would only add a bootstrap-window
# hop. infra/ owns the *repository*; admin owns what CI is allowed to know.
#
# Secret vs variable is NOT the GitLab masked/unmasked split, and reusing
# local.terraform_ci_vars_unmasked here would be wrong. That list exists
# because GitLab can only mask a single-line value of >=8 characters with no
# '@' -- a platform constraint, not a judgement about sensitivity.
# TF_VAR_ssh_public_key is on it partly for that reason too -- the trailing
# user@host comment on a public key contains an '@'. GitHub has no such
# limit, so the default here is secret, and the exceptions are the values that
# are genuinely public:
#
#   ssh_public_key      the public half of a keypair
#   cloudflare_account_id  an identifier, not a credential
#   ci_app_id / client_id  visible to anyone who can see the App
#   *_rotated_at        apply timestamps, and the ones apps/ reads to compute
#                       secret ages -- see project_secret_age_tracking
#
# Keeping those as variables is not cosmetic: GitHub redacts every occurrence
# of a secret value in logs, so making a 7-character App ID a secret would
# blank that digit string wherever it appeared, and masking the rotated_at
# timestamps would turn every plan diff that touches them into `***`.
locals {
  terraform_github_public = [
    "TF_VAR_ssh_public_key",
    "TF_VAR_cloudflare_account_id",
    "TF_VAR_ci_app_id",
    "TF_VAR_terraform_app_id",
    "TF_VAR_terraform_app_installation_id",
    "TF_VAR_ci_app_client_id",
    "TF_VAR_discord_bot_token_rotated_at",
    "TF_VAR_discord_management_token_rotated_at",
    "TF_VAR_cloudflare_api_token_rotated_at",
    "TF_VAR_cloudflare_dns01_token_rotated_at",
    "TF_VAR_gitlab_api_key_rotated_at",
    "TF_VAR_gitlab_ci_api_key_rotated_at",
    "TF_VAR_ssh_public_key_rotated_at",
    "TF_VAR_ci_app_private_key_rotated_at",
    "TF_VAR_gitlab_ci_service_account_id",
  ]

  # Empty, and kept rather than deleted: GitHub rejects any secret or variable
  # name beginning with GITHUB_, so anything added to terraform_ci_vars with
  # that prefix has to be listed here or the apply fails. GITHUB_BOT_TOKEN was
  # the only entry until 2026-09-05, when it was removed as orphaned -- Renovate
  # needed a separate github.com token for release-note lookups on GitLab, and
  # on GitHub the platform token covers changelogs.
  terraform_github_excluded = []

  terraform_github_secrets = {
    for key, value in local.terraform_ci_vars : key => value
    if !contains(local.terraform_github_excluded, key)
    && !contains(local.terraform_github_public, key)
  }

  terraform_github_variables = {
    for key, value in local.terraform_ci_vars : key => value
    if !contains(local.terraform_github_excluded, key)
    && contains(local.terraform_github_public, key)
  }
}

# The repository itself is created by terraform/infra (module.terraform_repo);
# only its Actions credentials are owned here. That split is deliberate but it
# does mean an ordering constraint: infra/ must have applied once before this
# resource can find the repo.
resource "github_actions_secret" "terraform" {
  for_each = local.terraform_github_secrets

  repository      = "terraform"
  secret_name     = each.key
  plaintext_value = each.value
}

resource "github_actions_variable" "terraform" {
  for_each = local.terraform_github_variables

  repository    = "terraform"
  variable_name = each.key
  value         = each.value
}

# ==============================================================================
# The `terraform` repo itself.
#
# Moved here from terraform/infra on 2026-09-04, because a stack must not own
# the repository its own CI runs from. infra/ is applied BY tnoff/terraform's
# CI, so while infra/ owned that repo an apply could delete the secrets its own
# next run needs to authenticate -- and the fix would have to be applied by the
# CI that could no longer start. Not theoretical: on 2026-09-04 a config that
# had merely fallen behind its state would have destroyed all four OCI_*
# secrets on the next apply. admin is applied locally, outside CI, so it can
# always recover what CI stands on.
#
# It also restores the symmetry the GitLab side always had -- see
# module.terraform_gitlab above, whose comment already claimed admin was "the
# only stack that interacts with the terraform GitLab project".
#
# tnoff/terraform-admin -- THIS repo -- is deliberately NOT here, and is not in
# infra either. A stack owning its own housing is the bootstrap paradox in
# miniature: something has to exist before terraform can run, and for the
# layer-0 stack that something is its own repository, exactly like the local
# state file this stack keeps outside the repo tree. It is created and
# configured by hand.
#
# The cost of that, stated plainly so it is not discovered during a rotation:
# this repo's CI_APP_* Actions secrets are managed by nothing. They were
# written by infra and survive as unmanaged values. When the tnoff-ci App key
# rotates, every other repo picks it up from an apply and THIS one needs:
#
#   gh secret set CI_APP_PRIVATE_KEY --repo tnoff/terraform-admin < key.pem
#
# See var.ci_app_private_key_b64 and time_static.ci_app_private_key_rotated_at.
#
# Only the App credentials are set below. The ~18 values that are genuinely
# "what CI is allowed to know" continue to come from
# github_actions_secret.terraform above, off the same map that feeds the GitLab
# pipeline variables.
#
# No bypass_actors: the module gates its ruleset on `var.is_public &&
# var.enable_ruleset`, and this repo is private, so no ruleset exists for an
# actor to bypass. Rulesets on private repos need GitHub Pro.
module "terraform_repo" {
  source    = "git::https://github.com/tnoff/terraform-modules.git//github/repo?ref=a853c6f188e873ec24c43e9868c99be1bf015bb9"
  repo_name = "terraform"

  repo_description = "Layer-1 infrastructure: OKE, networking, apps, DNS, Discord and the GitHub/GitLab repo fleet"
  topics           = ["terraform", "terragrunt", "oci", "kubernetes", "infrastructure"]

  # PRIVATE. Every OCID, subnet CIDR, bucket name and cluster detail in the
  # tenancy is in this repo's state and variables.
  is_public  = false
  auto_init  = true
  has_issues = true

  # The same three secrets infra writes to every flipped repo, from the same
  # admin inputs infra receives them through.
  action_secrets = {
    CI_APP_ID          = var.ci_app_id
    CI_APP_CLIENT_ID   = var.ci_app_client_id
    CI_APP_PRIVATE_KEY = base64decode(var.ci_app_private_key_b64)
  }
}
