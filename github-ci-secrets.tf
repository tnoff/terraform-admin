# ==============================================================================
# The CI credentials, on GitHub.
#
# tnoff/terraform runs its plan/apply on GitHub Actions, so every value in
# local.terraform_ci_vars is pushed here. It lives in admin because admin
# already owns these values, and having infra/ relay them would only add a
# bootstrap-window hop. infra/ owns the *repository*; admin owns what CI is
# allowed to know.
#
# The default is secret, and the exceptions are the values that are genuinely
# public:
#
#   ssh_public_key      the public half of a keypair
#   cloudflare_account_id  an identifier, not a credential
#   OCI_NAMESPACE       the Object Storage namespace; it is also the tenancy
#                       name, so as a secret it would mask that word, repo
#                       names included, everywhere in the logs
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
    "OCI_NAMESPACE",
    "TF_VAR_ssh_public_key",
    "TF_VAR_cloudflare_account_id",
    "TF_VAR_ci_app_id",
    "TF_VAR_terraform_app_id",
    "TF_VAR_terraform_app_installation_id",
    "TF_VAR_ci_app_client_id",
    "TF_VAR_changelog_app_id",
    "TF_VAR_changelog_app_client_id",
    "TF_VAR_discord_bot_token_rotated_at",
    "TF_VAR_discord_management_token_rotated_at",
    "TF_VAR_cloudflare_api_token_rotated_at",
    "TF_VAR_openweather_api_key_rotated_at",
    "TF_VAR_bart_api_key_rotated_at",
    "TF_VAR_five11_api_key_rotated_at",
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
    "TF_VAR_ssh_public_key_rotated_at",
    "TF_VAR_ci_app_private_key_rotated_at",
    "TF_VAR_changelog_app_private_key_rotated_at",
    "TF_VAR_terraform_app_private_key_rotated_at",
    "TF_VAR_oidc_exchange_client_secret_rotated_at",
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

# The repository itself is module.terraform_repo below (moved here from
# terraform/infra on 2026-09-04); these are its Actions credentials.
resource "github_actions_secret" "terraform" {
  for_each = local.terraform_github_secrets

  repository  = "terraform"
  secret_name = each.key
  value       = each.value
}

resource "github_actions_variable" "terraform" {
  for_each = local.terraform_github_variables

  repository    = "terraform"
  variable_name = each.key
  value         = each.value
}

# The same exchange domain URL and client id, as variables, ADDITIONALLY to the secrets above.
# terraform's own workflows read them as secrets (the oci-oidc-login action), so they stay secrets;
# a reusable-workflow call cannot read the `secrets` context in `with:`, and the TechDocs publish
# (techdocs-publish-oidc.yml) takes both as inputs, so it reads `vars.*`. Neither value is a
# credential on its own (the client secret is only useful with a token the trust accepts).
resource "github_actions_variable" "terraform_oidc_exchange" {
  for_each = {
    OIDC_EXCHANGE_DOMAIN_URL = local.terraform_ci_vars["OIDC_EXCHANGE_DOMAIN_URL"]
    OIDC_EXCHANGE_CLIENT_ID  = local.terraform_ci_vars["OIDC_EXCHANGE_CLIENT_ID"]
  }

  repository    = "terraform"
  variable_name = each.key
  value         = each.value
}
