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
  source = "git::https://github.com/tnoff/terraform-modules.git//oci/secret-vault?ref=bafeb496d73eb5d8e018cfd9edddfb61ab14e2a4"

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
  source                          = "git::https://github.com/tnoff/terraform-modules.git//oci/object-storage-bucket?ref=bafeb496d73eb5d8e018cfd9edddfb61ab14e2a4"
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
# IAM Resources - Cluster CI User
#
# The identity for terraform's apply:apps job and its plan job; dns/ has its own
# user below (tnoff/terraform#116). Until this existed those jobs ran as terraform_admin,
# which holds `manage all-resources` tenancy-wide and which OKE maps to
# cluster-admin, so a compromised apps/ or dns/ job could rewrite IAM or touch
# any workload. This user can do exactly four things:
#
#   1. open and delete bastion sessions (the tunnel to the private API); that
#      includes reading the compute and network resources a session is built on,
#   2. authenticate to the OKE API (`use clusters`; NOT `manage`, which is what
#      OKE turns into cluster-admin),
#   3. read and write the apps/ state bucket,
#   4. read the state buckets in var.cluster_ci_state_read_workspaces, which
#      apps/ reads through terraform_remote_state.
#
# What it may do INSIDE the cluster is not decided here. It gets no implicit
# cluster-admin, so tnoff/terraform's bootstrap/ stack binds it to the narrow
# Secret/ConfigMap/Service ClusterRoles by user OCID. That binding is applied
# by the operator, never by CI, so CI cannot widen its own access.
#
# Known limit: object storage cannot scope reads to a state file's outputs, so
# `read objects` on a bucket exposes everything in that state file (bot
# credentials included), so var.cluster_ci_state_read_workspaces should list
# only stacks whose outputs apps/ really reads. The user still cannot write
# them, touch IAM, or reach any other tenancy resource.
# ==============================================================================

resource "tls_private_key" "cluster_ci" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "oci_identity_user" "cluster_ci" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Scoped user for terraform's apps/ and dns/ CI jobs: bastion tunnel, OKE API, state buckets"
  name           = var.cluster_ci_user_name

  freeform_tags = {
    "Purpose"   = "terraform-cluster-ci"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

resource "oci_identity_api_key" "cluster_ci" {
  user_id   = oci_identity_user.cluster_ci.id
  key_value = tls_private_key.cluster_ci.public_key_pem
}

resource "oci_identity_group" "cluster_ci" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Scoped group for terraform's apps/ and dns/ CI jobs"
  name           = var.cluster_ci_group_name

  freeform_tags = {
    "Purpose"   = "terraform-cluster-ci"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

resource "oci_identity_user_group_membership" "cluster_ci" {
  group_id = oci_identity_group.cluster_ci.id
  user_id  = oci_identity_user.cluster_ci.id
}

resource "oci_identity_policy" "cluster_ci" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Scoped policy for terraform's apps/ and dns/ CI jobs"
  name           = "terraform-cluster-ci-policy"

  statements = [
    "Allow group ${oci_identity_group.cluster_ci.name} to manage bastion-session in compartment ${var.cluster_ci_compartment_name}",
    # CreateSession and DeleteSession need BASTION_USE (`use bastion`, which also
    # covers listing and reading the bastion), and CreateSession reads the
    # target's compute and network resources. These are the exact permissions in
    # Oracle's Bastion policy reference, as narrow resource types rather than the
    # documentation examples' `manage virtual-network-family`.
    "Allow group ${oci_identity_group.cluster_ci.name} to use bastion in compartment ${var.cluster_ci_compartment_name}",
    "Allow group ${oci_identity_group.cluster_ci.name} to read instances in compartment ${var.cluster_ci_compartment_name}",
    "Allow group ${oci_identity_group.cluster_ci.name} to read instance-agent-plugins in compartment ${var.cluster_ci_compartment_name}",
    "Allow group ${oci_identity_group.cluster_ci.name} to read vnic-attachments in compartment ${var.cluster_ci_compartment_name}",
    "Allow group ${oci_identity_group.cluster_ci.name} to read vnics in compartment ${var.cluster_ci_compartment_name}",
    "Allow group ${oci_identity_group.cluster_ci.name} to read subnets in compartment ${var.cluster_ci_compartment_name}",
    "Allow group ${oci_identity_group.cluster_ci.name} to read vcns in compartment ${var.cluster_ci_compartment_name}",
    "Allow group ${oci_identity_group.cluster_ci.name} to use clusters in compartment ${var.cluster_ci_compartment_name}",
    "Allow group ${oci_identity_group.cluster_ci.name} to manage objects in tenancy where any {${join(", ", [for w in var.cluster_ci_state_write_workspaces : "target.bucket.name = '${var.state_bucket_prefix}-${w}'"])}}",
    "Allow group ${oci_identity_group.cluster_ci.name} to read objects in tenancy where any {${join(", ", [for w in var.cluster_ci_state_read_workspaces : "target.bucket.name = '${var.state_bucket_prefix}-${w}'"])}}",
  ]

  freeform_tags = {
    "Purpose"   = "terraform-cluster-ci"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

# ==============================================================================
# IAM Resources - DNS CI User
#
# The identity for terraform's apply:dns / plan:dns jobs (tnoff/terraform#116).
# dns/ reads no other stack's state, so unlike the apps/ user this one gets
# write on the dns state bucket and nothing else beyond the cluster path
# (bastion session + OKE API; dns/ looks up the ingress-nginx Service). Its
# in-cluster access is `services` read in ingress-nginx, bound by bootstrap/.
# ==============================================================================

locals {
  # What reaching the private OKE API through the bastion takes. The same set the
  # apps/ user holds; see the comment on oci_identity_policy.cluster_ci.
  cluster_path_grants = [
    "manage bastion-session",
    "use bastion",
    "read instances",
    "read instance-agent-plugins",
    "read vnic-attachments",
    "read vnics",
    "read subnets",
    "read vcns",
    "use clusters",
  ]
}

resource "tls_private_key" "dns_ci" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "oci_identity_user" "dns_ci" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Scoped user for terraform's dns/ CI job: bastion tunnel, OKE API, dns state bucket"
  name           = var.dns_ci_user_name

  freeform_tags = {
    "Purpose"   = "terraform-dns-ci"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

resource "oci_identity_api_key" "dns_ci" {
  user_id   = oci_identity_user.dns_ci.id
  key_value = tls_private_key.dns_ci.public_key_pem
}

resource "oci_identity_group" "dns_ci" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Scoped group for terraform's dns/ CI job"
  name           = var.dns_ci_group_name

  freeform_tags = {
    "Purpose"   = "terraform-dns-ci"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

resource "oci_identity_user_group_membership" "dns_ci" {
  group_id = oci_identity_group.dns_ci.id
  user_id  = oci_identity_user.dns_ci.id
}

resource "oci_identity_policy" "dns_ci" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Scoped policy for terraform's dns/ CI job"
  name           = "terraform-dns-ci-policy"

  statements = concat(
    [
      for grant in local.cluster_path_grants :
      "Allow group ${oci_identity_group.dns_ci.name} to ${grant} in compartment ${var.cluster_ci_compartment_name}"
    ],
    [
      "Allow group ${oci_identity_group.dns_ci.name} to manage objects in tenancy where any {${join(", ", [for w in var.dns_ci_state_write_workspaces : "target.bucket.name = '${var.state_bucket_prefix}-${w}'"])}}",
    ],
  )

  freeform_tags = {
    "Purpose"   = "terraform-dns-ci"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

# ==============================================================================
# IAM Resources - state-only CI users (infra/ and discord/)
#
# Neither stack uses the OCI provider; they authenticated as terraform-admin only
# to reach their state buckets (infra/ also reads the oci and discord states).
# Each gets a user with `manage objects` on its own state bucket, `read objects`
# on the stacks it reads, and nothing else (tnoff/terraform#116). Keyed by stack
# in var.state_ci_users; the credentials reach CI as INFRA_CI_OCI_* and
# DISCORD_CI_OCI_*.
# ==============================================================================

resource "tls_private_key" "state_ci" {
  for_each  = var.state_ci_users
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "oci_identity_user" "state_ci" {
  for_each       = var.state_ci_users
  compartment_id = var.oci_tenancy_ocid
  description    = "Scoped user for terraform's ${each.key}/ CI job: its state bucket only"
  name           = each.value.user_name

  freeform_tags = {
    "Purpose"   = "terraform-${each.key}-ci"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

resource "oci_identity_api_key" "state_ci" {
  for_each  = var.state_ci_users
  user_id   = oci_identity_user.state_ci[each.key].id
  key_value = tls_private_key.state_ci[each.key].public_key_pem
}

resource "oci_identity_group" "state_ci" {
  for_each       = var.state_ci_users
  compartment_id = var.oci_tenancy_ocid
  description    = "Scoped group for terraform's ${each.key}/ CI job"
  name           = each.value.group_name

  freeform_tags = {
    "Purpose"   = "terraform-${each.key}-ci"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

resource "oci_identity_user_group_membership" "state_ci" {
  for_each = var.state_ci_users
  group_id = oci_identity_group.state_ci[each.key].id
  user_id  = oci_identity_user.state_ci[each.key].id
}

resource "oci_identity_policy" "state_ci" {
  for_each       = var.state_ci_users
  compartment_id = var.oci_tenancy_ocid
  description    = "Scoped policy for terraform's ${each.key}/ CI job: state buckets only"
  name           = "terraform-${each.key}-ci-policy"

  statements = concat(
    [
      "Allow group ${oci_identity_group.state_ci[each.key].name} to manage objects in tenancy where any {${join(", ", [for w in each.value.state_write_workspaces : "target.bucket.name = '${var.state_bucket_prefix}-${w}'"])}}",
    ],
    # An empty `any {}` is invalid, so a stack that reads no other state gets no
    # read statement at all.
    length(each.value.state_read_workspaces) == 0 ? [] : [
      "Allow group ${oci_identity_group.state_ci[each.key].name} to read objects in tenancy where any {${join(", ", [for w in each.value.state_read_workspaces : "target.bucket.name = '${var.state_bucket_prefix}-${w}'"])}}",
    ],
  )

  freeform_tags = {
    "Purpose"   = "terraform-${each.key}-ci"
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

    # bootstrap/ binds this user to its narrow ClusterRoles by OCID. .envrc ONLY:
    # bootstrap is operator-applied and never runs in CI.
    TF_VAR_cluster_ci_user_ocid = oci_identity_user.cluster_ci.id
    TF_VAR_dns_ci_user_ocid     = oci_identity_user.dns_ci.id

    # The GitHub OIDC spike's federated service user (oidc-spike.tf), bound by
    # bootstrap/ the same way. Delete with oidc-spike.tf if the spike is a no-go.
    TF_VAR_oidc_spike_user_ocid = oci_identity_domains_user.oidc_spike.ocid

    TF_VAR_cloudflare_api_token   = var.cloudflare_api_token
    TF_VAR_cloudflare_dns01_token = var.cloudflare_dns01_token
    TF_VAR_cloudflare_account_id  = var.cloudflare_account_id

    # discord_bot_token: back to being pushed, as of the incident on
    # 2026-09-21 -- see its description in variables.tf for why. It is now
    # consumed for real, by apps/'s kubernetes_secret_v1.discord_bot_token,
    # not just carried for no reason.
    TF_VAR_discord_bot_token        = var.discord_bot_token
    TF_VAR_discord_management_token = var.discord_management_token

    # OpenWeather API key -- pushed as of 2026-09-20, consumed for real by
    # apps/'s kubernetes_secret_v1.openweather_api_key. See its description
    # in variables.tf.
    TF_VAR_openweather_api_key = var.openweather_api_key

    # 511.org transit token (BART_API_KEY in docker-apps) -- pushed as of
    # 2026-09-21, consumed for real by apps/'s kubernetes_secret_v1.bart_api_key.
    # See its description in variables.tf.
    TF_VAR_bart_api_key = var.bart_api_key

    # Backstage externalAccess static token for the local MCP client -- pushed
    # as of 2026-09-28, consumed for real by apps/'s
    # kubernetes_secret_v1.backstage_mcp_token. See its description in
    # variables.tf.
    TF_VAR_backstage_mcp_token = var.backstage_mcp_token

    # hathor (docker-apps apps/hathor/): Mullvad device key + address for its
    # gluetun sidecar (and the server pool it picks from), the URL-path token that is the whole auth on its public
    # endpoint, its Google/Twitch API creds, and the yt-dlp cookies file (already
    # base64, one line). Consumed by apps/'s kubernetes_secret_v1.hathor_*. See
    # their descriptions in variables.tf.
    TF_VAR_hathor_vpn_private_key      = var.hathor_vpn_private_key
    TF_VAR_hathor_vpn_addresses        = var.hathor_vpn_addresses
    TF_VAR_hathor_vpn_server_hostnames = var.hathor_vpn_server_hostnames
    TF_VAR_hathor_url_token            = var.hathor_url_token
    TF_VAR_hathor_google_api_key       = var.hathor_google_api_key
    TF_VAR_hathor_twitch_client_id     = var.hathor_twitch_client_id
    TF_VAR_hathor_twitch_client_secret = var.hathor_twitch_client_secret
    TF_VAR_hathor_youtube_cookies_b64  = var.hathor_youtube_cookies_b64

    # discord's Spotify/YouTube search creds + VPN key, and eastbay's website
    # secrets -- pushed as of 2026-09-21, consumed for real by apps/'s
    # kubernetes_secret_v1.discord_search_creds/discord_vpn_key/eastbay_website_creds.
    # See their descriptions in variables.tf.
    TF_VAR_discord_spotify_client_id     = var.discord_spotify_client_id
    TF_VAR_discord_spotify_client_secret = var.discord_spotify_client_secret
    TF_VAR_discord_youtube_api_key       = var.discord_youtube_api_key
    TF_VAR_discord_vpn_private_key       = var.discord_vpn_private_key
    # base64-wrapped, not left plain like every other TF_VAR_ here: neither
    # value fits GitLab's masked-variable charset (an email always has '@';
    # a formatted phone number routinely carries punctuation the charset
    # rejects), and unmasking a value just to satisfy that check means any
    # stray echo of it -- a plan, an error, a debug step -- sits in CI job
    # log history indefinitely, rotation or not. base64 keeps it masked
    # (output is pure Base64-alphabet, safely >= 8 chars for any realistic
    # email/phone number) instead of giving that up. terraform/apps'
    # kubernetes_secret_v1.eastbay_website_creds base64decode()s it back.
    TF_VAR_eastbay_contact_email       = base64encode(var.eastbay_contact_email)
    TF_VAR_eastbay_contact_number      = base64encode(var.eastbay_contact_number)
    TF_VAR_eastbay_email_host_user     = var.eastbay_email_host_user
    TF_VAR_eastbay_email_host_password = var.eastbay_email_host_password
    TF_VAR_eastbay_flask_secret_key    = var.eastbay_flask_secret_key

    # Grafana's bootstrap admin credential -- base64-wrapped defensively (see
    # variables.tf; a short 'admin' username fails GitLab's >= 8 char check
    # outright, and the password gets the same treatment on general
    # principle). apps/'s kubernetes_secret_v1.grafana_admin decodes both.
    TF_VAR_grafana_admin_user     = base64encode(var.grafana_admin_user)
    TF_VAR_grafana_admin_password = base64encode(var.grafana_admin_password)

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

    # tnoff-flux App -- Flux's read credential for docker-apps, phase 7. Local
    # .envrc ONLY: consumed by the operator-run bootstrap stack, and nothing
    # in CI has any use for it.
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
    TF_VAR_discord_bot_token_rotated_at             = time_static.discord_bot_token_rotated_at.rfc3339
    TF_VAR_discord_management_token_rotated_at      = time_static.discord_management_token_rotated_at.rfc3339
    TF_VAR_cloudflare_api_token_rotated_at          = time_static.cloudflare_api_token_rotated_at.rfc3339
    TF_VAR_cloudflare_dns01_token_rotated_at        = time_static.cloudflare_dns01_token_rotated_at.rfc3339
    TF_VAR_openweather_api_key_rotated_at           = time_static.openweather_api_key_rotated_at.rfc3339
    TF_VAR_bart_api_key_rotated_at                  = time_static.bart_api_key_rotated_at.rfc3339
    TF_VAR_backstage_mcp_token_rotated_at           = time_static.backstage_mcp_token_rotated_at.rfc3339
    TF_VAR_hathor_vpn_private_key_rotated_at        = time_static.hathor_vpn_private_key_rotated_at.rfc3339
    TF_VAR_hathor_url_token_rotated_at              = time_static.hathor_url_token_rotated_at.rfc3339
    TF_VAR_hathor_google_api_key_rotated_at         = time_static.hathor_google_api_key_rotated_at.rfc3339
    TF_VAR_hathor_twitch_client_secret_rotated_at   = time_static.hathor_twitch_client_secret_rotated_at.rfc3339
    TF_VAR_hathor_youtube_cookies_rotated_at        = time_static.hathor_youtube_cookies_rotated_at.rfc3339
    TF_VAR_discord_spotify_client_id_rotated_at     = time_static.discord_spotify_client_id_rotated_at.rfc3339
    TF_VAR_discord_spotify_client_secret_rotated_at = time_static.discord_spotify_client_secret_rotated_at.rfc3339
    TF_VAR_discord_youtube_api_key_rotated_at       = time_static.discord_youtube_api_key_rotated_at.rfc3339
    TF_VAR_discord_vpn_private_key_rotated_at       = time_static.discord_vpn_private_key_rotated_at.rfc3339
    TF_VAR_eastbay_contact_email_rotated_at         = time_static.eastbay_contact_email_rotated_at.rfc3339
    TF_VAR_eastbay_contact_number_rotated_at        = time_static.eastbay_contact_number_rotated_at.rfc3339
    TF_VAR_eastbay_email_host_user_rotated_at       = time_static.eastbay_email_host_user_rotated_at.rfc3339
    TF_VAR_eastbay_email_host_password_rotated_at   = time_static.eastbay_email_host_password_rotated_at.rfc3339
    TF_VAR_eastbay_flask_secret_key_rotated_at      = time_static.eastbay_flask_secret_key_rotated_at.rfc3339
    TF_VAR_grafana_admin_user_rotated_at            = time_static.grafana_admin_user_rotated_at.rfc3339
    TF_VAR_grafana_admin_password_rotated_at        = time_static.grafana_admin_password_rotated_at.rfc3339
    TF_VAR_gitlab_api_key_rotated_at                = time_static.gitlab_api_key_rotated_at.rfc3339
    TF_VAR_gitlab_ci_api_key_rotated_at             = time_static.gitlab_ci_api_key_rotated_at.rfc3339
    TF_VAR_ssh_public_key_rotated_at                = time_static.ssh_public_key_rotated_at.rfc3339
    TF_VAR_ci_app_private_key_rotated_at            = time_static.ci_app_private_key_rotated_at.rfc3339

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

    # The scoped identity for the apps/ and dns/ jobs (tnoff/terraform#116).
    # Deliberately NOT OCI_* / TF_VAR_oci_*: the terragrunt composite action
    # exports only those prefixes, so these stay out of every job's
    # environment until a workflow passes them to a step by name.
    CLUSTER_CI_OCI_USER_OCID   = oci_identity_user.cluster_ci.id
    CLUSTER_CI_OCI_FINGERPRINT = oci_identity_api_key.cluster_ci.fingerprint
    CLUSTER_CI_OCI_API_KEY_B64 = base64encode(tls_private_key.cluster_ci.private_key_pem)

    # The dns/ job's own identity (tnoff/terraform#116). Same reasoning.
    DNS_CI_OCI_USER_OCID   = oci_identity_user.dns_ci.id
    DNS_CI_OCI_FINGERPRINT = oci_identity_api_key.dns_ci.fingerprint
    DNS_CI_OCI_API_KEY_B64 = base64encode(tls_private_key.dns_ci.private_key_pem)

    # The infra/ and discord/ jobs' own identities (tnoff/terraform#116).
    INFRA_CI_OCI_USER_OCID   = oci_identity_user.state_ci["infra"].id
    INFRA_CI_OCI_FINGERPRINT = oci_identity_api_key.state_ci["infra"].fingerprint
    INFRA_CI_OCI_API_KEY_B64 = base64encode(tls_private_key.state_ci["infra"].private_key_pem)

    DISCORD_CI_OCI_USER_OCID   = oci_identity_user.state_ci["discord"].id
    DISCORD_CI_OCI_FINGERPRINT = oci_identity_api_key.state_ci["discord"].fingerprint
    DISCORD_CI_OCI_API_KEY_B64 = base64encode(tls_private_key.state_ci["discord"].private_key_pem)

    # The GitHub OIDC spike's token-exchange app (tnoff/terraform#135, see
    # oidc-spike.tf). Not OCI_*-prefixed, for the same reason as the scoped
    # users above. The secret is only useful together with a GitHub token the
    # trust accepts. Delete these three with oidc-spike.tf if the spike is a no-go.
    OIDC_EXCHANGE_DOMAIN_URL    = local.oidc_spike_domain_endpoint
    OIDC_EXCHANGE_CLIENT_ID     = oci_identity_domains_app.oidc_spike_exchange.name
    OIDC_EXCHANGE_CLIENT_SECRET = oci_identity_domains_app.oidc_spike_exchange.client_secret

    TF_VAR_cloudflare_api_token   = var.cloudflare_api_token
    TF_VAR_cloudflare_dns01_token = var.cloudflare_dns01_token
    TF_VAR_cloudflare_account_id  = var.cloudflare_account_id

    # discord_bot_token: back to being pushed, as of the incident on
    # 2026-09-21 -- see its description in variables.tf for why. It is now
    # consumed for real, by apps/'s kubernetes_secret_v1.discord_bot_token,
    # not just carried for no reason.
    TF_VAR_discord_bot_token        = var.discord_bot_token
    TF_VAR_discord_management_token = var.discord_management_token

    # OpenWeather API key -- pushed as of 2026-09-20, consumed for real by
    # apps/'s kubernetes_secret_v1.openweather_api_key. See its description
    # in variables.tf.
    TF_VAR_openweather_api_key = var.openweather_api_key

    # 511.org transit token (BART_API_KEY in docker-apps) -- pushed as of
    # 2026-09-21, consumed for real by apps/'s kubernetes_secret_v1.bart_api_key.
    # See its description in variables.tf.
    TF_VAR_bart_api_key = var.bart_api_key

    # Backstage externalAccess static token for the local MCP client -- pushed
    # as of 2026-09-28, consumed for real by apps/'s
    # kubernetes_secret_v1.backstage_mcp_token. See its description in
    # variables.tf.
    TF_VAR_backstage_mcp_token = var.backstage_mcp_token

    # hathor (docker-apps apps/hathor/): Mullvad device key + address for its
    # gluetun sidecar (and the server pool it picks from), the URL-path token that is the whole auth on its public
    # endpoint, its Google/Twitch API creds, and the yt-dlp cookies file (already
    # base64, one line). Consumed by apps/'s kubernetes_secret_v1.hathor_*. See
    # their descriptions in variables.tf.
    TF_VAR_hathor_vpn_private_key      = var.hathor_vpn_private_key
    TF_VAR_hathor_vpn_addresses        = var.hathor_vpn_addresses
    TF_VAR_hathor_vpn_server_hostnames = var.hathor_vpn_server_hostnames
    TF_VAR_hathor_url_token            = var.hathor_url_token
    TF_VAR_hathor_google_api_key       = var.hathor_google_api_key
    TF_VAR_hathor_twitch_client_id     = var.hathor_twitch_client_id
    TF_VAR_hathor_twitch_client_secret = var.hathor_twitch_client_secret
    TF_VAR_hathor_youtube_cookies_b64  = var.hathor_youtube_cookies_b64

    # discord's Spotify/YouTube search creds + VPN key, and eastbay's website
    # secrets -- pushed as of 2026-09-21, consumed for real by apps/'s
    # kubernetes_secret_v1.discord_search_creds/discord_vpn_key/eastbay_website_creds.
    # See their descriptions in variables.tf.
    TF_VAR_discord_spotify_client_id     = var.discord_spotify_client_id
    TF_VAR_discord_spotify_client_secret = var.discord_spotify_client_secret
    TF_VAR_discord_youtube_api_key       = var.discord_youtube_api_key
    TF_VAR_discord_vpn_private_key       = var.discord_vpn_private_key
    # base64-wrapped, not left plain like every other TF_VAR_ here: neither
    # value fits GitLab's masked-variable charset (an email always has '@';
    # a formatted phone number routinely carries punctuation the charset
    # rejects), and unmasking a value just to satisfy that check means any
    # stray echo of it -- a plan, an error, a debug step -- sits in CI job
    # log history indefinitely, rotation or not. base64 keeps it masked
    # (output is pure Base64-alphabet, safely >= 8 chars for any realistic
    # email/phone number) instead of giving that up. terraform/apps'
    # kubernetes_secret_v1.eastbay_website_creds base64decode()s it back.
    TF_VAR_eastbay_contact_email       = base64encode(var.eastbay_contact_email)
    TF_VAR_eastbay_contact_number      = base64encode(var.eastbay_contact_number)
    TF_VAR_eastbay_email_host_user     = var.eastbay_email_host_user
    TF_VAR_eastbay_email_host_password = var.eastbay_email_host_password
    TF_VAR_eastbay_flask_secret_key    = var.eastbay_flask_secret_key

    # Grafana's bootstrap admin credential -- base64-wrapped defensively (see
    # variables.tf; a short 'admin' username fails GitLab's >= 8 char check
    # outright, and the password gets the same treatment on general
    # principle). apps/'s kubernetes_secret_v1.grafana_admin decodes both.
    TF_VAR_grafana_admin_user     = base64encode(var.grafana_admin_user)
    TF_VAR_grafana_admin_password = base64encode(var.grafana_admin_password)

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
    TF_VAR_discord_bot_token_rotated_at             = time_static.discord_bot_token_rotated_at.rfc3339
    TF_VAR_discord_management_token_rotated_at      = time_static.discord_management_token_rotated_at.rfc3339
    TF_VAR_cloudflare_api_token_rotated_at          = time_static.cloudflare_api_token_rotated_at.rfc3339
    TF_VAR_cloudflare_dns01_token_rotated_at        = time_static.cloudflare_dns01_token_rotated_at.rfc3339
    TF_VAR_openweather_api_key_rotated_at           = time_static.openweather_api_key_rotated_at.rfc3339
    TF_VAR_bart_api_key_rotated_at                  = time_static.bart_api_key_rotated_at.rfc3339
    TF_VAR_backstage_mcp_token_rotated_at           = time_static.backstage_mcp_token_rotated_at.rfc3339
    TF_VAR_hathor_vpn_private_key_rotated_at        = time_static.hathor_vpn_private_key_rotated_at.rfc3339
    TF_VAR_hathor_url_token_rotated_at              = time_static.hathor_url_token_rotated_at.rfc3339
    TF_VAR_hathor_google_api_key_rotated_at         = time_static.hathor_google_api_key_rotated_at.rfc3339
    TF_VAR_hathor_twitch_client_secret_rotated_at   = time_static.hathor_twitch_client_secret_rotated_at.rfc3339
    TF_VAR_hathor_youtube_cookies_rotated_at        = time_static.hathor_youtube_cookies_rotated_at.rfc3339
    TF_VAR_discord_spotify_client_id_rotated_at     = time_static.discord_spotify_client_id_rotated_at.rfc3339
    TF_VAR_discord_spotify_client_secret_rotated_at = time_static.discord_spotify_client_secret_rotated_at.rfc3339
    TF_VAR_discord_youtube_api_key_rotated_at       = time_static.discord_youtube_api_key_rotated_at.rfc3339
    TF_VAR_discord_vpn_private_key_rotated_at       = time_static.discord_vpn_private_key_rotated_at.rfc3339
    TF_VAR_eastbay_contact_email_rotated_at         = time_static.eastbay_contact_email_rotated_at.rfc3339
    TF_VAR_eastbay_contact_number_rotated_at        = time_static.eastbay_contact_number_rotated_at.rfc3339
    TF_VAR_eastbay_email_host_user_rotated_at       = time_static.eastbay_email_host_user_rotated_at.rfc3339
    TF_VAR_eastbay_email_host_password_rotated_at   = time_static.eastbay_email_host_password_rotated_at.rfc3339
    TF_VAR_eastbay_flask_secret_key_rotated_at      = time_static.eastbay_flask_secret_key_rotated_at.rfc3339
    TF_VAR_grafana_admin_user_rotated_at            = time_static.grafana_admin_user_rotated_at.rfc3339
    TF_VAR_grafana_admin_password_rotated_at        = time_static.grafana_admin_password_rotated_at.rfc3339
    TF_VAR_gitlab_api_key_rotated_at                = time_static.gitlab_api_key_rotated_at.rfc3339
    TF_VAR_gitlab_ci_api_key_rotated_at             = time_static.gitlab_ci_api_key_rotated_at.rfc3339
    TF_VAR_ssh_public_key_rotated_at                = time_static.ssh_public_key_rotated_at.rfc3339
    TF_VAR_ci_app_private_key_rotated_at            = time_static.ci_app_private_key_rotated_at.rfc3339

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
    "TF_VAR_openweather_api_key_rotated_at",
    "TF_VAR_bart_api_key_rotated_at",
    "TF_VAR_backstage_mcp_token_rotated_at",
    "TF_VAR_hathor_vpn_private_key_rotated_at",
    "TF_VAR_hathor_url_token_rotated_at",
    "TF_VAR_hathor_google_api_key_rotated_at",
    "TF_VAR_hathor_twitch_client_secret_rotated_at",
    "TF_VAR_hathor_youtube_cookies_rotated_at",
    "TF_VAR_discord_spotify_client_id_rotated_at",
    "TF_VAR_discord_spotify_client_secret_rotated_at",
    "TF_VAR_discord_youtube_api_key_rotated_at",
    "TF_VAR_discord_vpn_private_key_rotated_at",
    "TF_VAR_eastbay_contact_email_rotated_at",
    "TF_VAR_eastbay_contact_number_rotated_at",
    "TF_VAR_eastbay_email_host_user_rotated_at",
    "TF_VAR_eastbay_email_host_password_rotated_at",
    "TF_VAR_eastbay_flask_secret_key_rotated_at",
    "TF_VAR_grafana_admin_user_rotated_at",
    "TF_VAR_grafana_admin_password_rotated_at",
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
  source           = "git::https://github.com/tnoff/terraform-modules.git//gitlab/repo?ref=bafeb496d73eb5d8e018cfd9edddfb61ab14e2a4"
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

  # Off by default: see var.gitlab_ci_variables_enabled. This was the largest
  # copy of the CI secrets outside GitHub -- the admin OCI API key and every
  # TF_VAR_* value -- sitting in a project that runs nothing.
  pipeline_variables = var.gitlab_ci_variables_enabled ? {
    for key, value in local.terraform_ci_vars :
    key => {
      value  = value
      masked = !contains(local.terraform_ci_vars_unmasked, key)
    }
  } : {}
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
    "TF_VAR_openweather_api_key_rotated_at",
    "TF_VAR_bart_api_key_rotated_at",
    "TF_VAR_backstage_mcp_token_rotated_at",
    "TF_VAR_hathor_vpn_private_key_rotated_at",
    "TF_VAR_hathor_url_token_rotated_at",
    "TF_VAR_hathor_google_api_key_rotated_at",
    "TF_VAR_hathor_twitch_client_secret_rotated_at",
    "TF_VAR_hathor_youtube_cookies_rotated_at",
    "TF_VAR_discord_spotify_client_id_rotated_at",
    "TF_VAR_discord_spotify_client_secret_rotated_at",
    "TF_VAR_discord_youtube_api_key_rotated_at",
    "TF_VAR_discord_vpn_private_key_rotated_at",
    "TF_VAR_eastbay_contact_email_rotated_at",
    "TF_VAR_eastbay_contact_number_rotated_at",
    "TF_VAR_eastbay_email_host_user_rotated_at",
    "TF_VAR_eastbay_email_host_password_rotated_at",
    "TF_VAR_eastbay_flask_secret_key_rotated_at",
    "TF_VAR_grafana_admin_user_rotated_at",
    "TF_VAR_grafana_admin_password_rotated_at",
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
    if !contains(local.terraform_github_excluded, key) && !contains(local.terraform_github_public, key)
  }

  terraform_github_variables = {
    for key, value in local.terraform_ci_vars : key => value
    if !contains(local.terraform_github_excluded, key) && contains(local.terraform_github_public, key)
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

# Issue-triage labels, same set infra/repos.tf applies to every other GitHub
# repo (local.triage_labels there). Duplicated rather than shared because this
# stack and infra are separate states. Triage is manual -- the untriaged queue
# is a search for open issues without `triaged` -- so keep `triaged` out of
# issue templates, whose `labels:` field applies even for outside reporters.
locals {
  triage_labels = {
    "priority/high"   = "d73a4a"
    "priority/medium" = "fbca04"
    "priority/low"    = "c5def5"
    "triaged"         = "5319e7"
  }
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
  source    = "git::https://github.com/tnoff/terraform-modules.git//github/repo?ref=bafeb496d73eb5d8e018cfd9edddfb61ab14e2a4"
  repo_name = "terraform"

  repo_description = "Layer-1 infrastructure: OKE, networking, apps, DNS, Discord and the GitHub/GitLab repo fleet"
  topics           = ["terraform", "terragrunt", "oci", "kubernetes", "infrastructure"]

  # PRIVATE. Every OCID, subnet CIDR, bucket name and cluster detail in the
  # tenancy is in this repo's state and variables.
  is_public  = false
  auto_init  = true
  has_issues = true

  # Public repos get Dependabot alerts unconditionally; private repos need
  # this set explicitly. Free on every plan tier -- checked before landing
  # this, not assumed.
  enable_vulnerability_alerts = true

  repo_labels = local.triage_labels

  # The same three secrets infra writes to every flipped repo, from the same
  # admin inputs infra receives them through.
  action_secrets = {
    CI_APP_ID          = var.ci_app_id
    CI_APP_CLIENT_ID   = var.ci_app_client_id
    CI_APP_PRIVATE_KEY = base64decode(var.ci_app_private_key_b64)
  }
}
