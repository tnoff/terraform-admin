# ==============================================================================
# Values pushed to `terraform`'s GitHub Actions secrets/variables (see
# terraform_github_secrets in github-ci-secrets.tf), AND exported from .envrc for local dev. PEM goes via OCI_API_KEY_B64 (base64-encoded,
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

    # Object Storage namespace of the state buckets, read by terraform's root.hcl
    # (backend) and passed on to its stacks' terraform_remote_state reads. Looked
    # up, never hardcoded, so terraform does not hardcode it either.
    OCI_NAMESPACE = data.oci_objectstorage_namespace.this.namespace

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

    # What tnoff/terraform's trust/ stack needs to plan and apply the GitHub trust from a
    # workstation (the trust is applied by -replace, which CI cannot do for itself). The same
    # values terraform_ci_vars pushes to CI; the .envrc is built from this map, not that one.
    TF_VAR_oidc_exchange_client_id  = oci_identity_domains_app.oidc_exchange.name
    TF_VAR_oidc_exchange_domain_url = local.oidc_domain_endpoint

    TF_VAR_cloudflare_api_token  = var.cloudflare_api_token
    TF_VAR_cloudflare_account_id = var.cloudflare_account_id

    # discord_bot_token: back to being pushed, as of the incident on
    # 2026-09-21 -- see its description in variables.tf for why. It is now
    # consumed for real, by apps/'s module.discord_bot_token,
    # not just carried for no reason.
    TF_VAR_discord_bot_token        = var.discord_bot_token
    TF_VAR_discord_management_token = var.discord_management_token

    # OpenWeather API key -- pushed as of 2026-09-20, consumed for real by
    # apps/'s module.openweather_api_key. See its description
    # in variables.tf.
    TF_VAR_openweather_api_key = var.openweather_api_key

    # 511.org transit token (BART_API_KEY in docker-apps) -- pushed as of
    # 2026-09-21, consumed for real by apps/'s module.bart_api_key.
    # See its description in variables.tf.
    TF_VAR_bart_api_key = var.bart_api_key

    # 511.org transit token (FIVE11_API_KEY in the mirror pods) -- consumed by
    # apps/'s module.five11_api_key. See its description in
    # variables.tf.
    TF_VAR_five11_api_key = var.five11_api_key

    # Backstage externalAccess static token for the local MCP client -- pushed
    # as of 2026-09-28, consumed for real by apps/'s
    # module.backstage_mcp_token. See its description in
    # variables.tf.
    TF_VAR_backstage_mcp_token = var.backstage_mcp_token

    # hathor (docker-apps apps/hathor/): Mullvad device key + address for its
    # gluetun sidecar (and the server pool it picks from), the URL-path token that is the whole auth on its public
    # endpoint, its Google/Twitch API creds, and the yt-dlp cookies file (already
    # base64, one line). Consumed by apps/'s module.hathor_*. See
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
    # module.discord_search_creds/discord_vpn_key/eastbay_website_creds.
    # See their descriptions in variables.tf.
    TF_VAR_discord_spotify_client_id     = var.discord_spotify_client_id
    TF_VAR_discord_spotify_client_secret = var.discord_spotify_client_secret
    TF_VAR_discord_youtube_api_key       = var.discord_youtube_api_key
    TF_VAR_discord_vpn_private_key       = var.discord_vpn_private_key
    TF_VAR_discord_vpn_addresses         = var.discord_vpn_addresses
    # base64-wrapped, not left plain like every other TF_VAR_ here: neither
    # value fits GitLab's masked-variable charset (an email always has '@';
    # a formatted phone number routinely carries punctuation the charset
    # rejects), and unmasking a value just to satisfy that check means any
    # stray echo of it -- a plan, an error, a debug step -- sits in CI job
    # log history indefinitely, rotation or not. base64 keeps it masked
    # (output is pure Base64-alphabet, safely >= 8 chars for any realistic
    # email/phone number) instead of giving that up. terraform/apps'
    # module.eastbay_website_creds base64decode()s it back.
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

    # The changelog App: contents write only, and the only ruleset bypass
    # actor. assemble-changelog is the one workflow that pushes straight to a
    # protected `main`, so it is the one that needs the bypass; tnoff-ci above
    # no longer does. Only infra/ declares these, to write CHANGELOG_APP_* onto
    # the repos that run assemble-changelog.
    TF_VAR_changelog_app_id              = var.changelog_app_id
    TF_VAR_changelog_app_client_id       = var.changelog_app_client_id
    TF_VAR_changelog_app_private_key_b64 = var.changelog_app_private_key_b64

    # tnoff-terraform App -- the identity infra/ manages GitHub with, replacing
    # the human admin PAT. Needs to reach CI as well as .envrc: apply:infra runs
    # the github provider on a hosted runner.
    TF_VAR_terraform_app_id              = var.terraform_app_id
    TF_VAR_terraform_app_installation_id = var.terraform_app_installation_id
    TF_VAR_terraform_app_private_key_b64 = var.terraform_app_private_key_b64
    TF_VAR_gitlab_api_key                = var.gitlab_api_key
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

    # tnoff-flux App -- Flux's read credential for docker-apps, phase 7. In the local
    # .envrc for a workstation run of the bootstrap stack. In CI the same values are
    # Environment secrets and variables on bootstrap-plan / bootstrap-apply only
    # (bootstrap-environments.tf), never repo-level ones.
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
    TF_VAR_openweather_api_key_rotated_at           = time_static.openweather_api_key_rotated_at.rfc3339
    TF_VAR_bart_api_key_rotated_at                  = time_static.bart_api_key_rotated_at.rfc3339
    TF_VAR_five11_api_key_rotated_at                = time_static.five11_api_key_rotated_at.rfc3339
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
    TF_VAR_ssh_public_key_rotated_at                = time_static.ssh_public_key_rotated_at.rfc3339
    TF_VAR_ci_app_private_key_rotated_at            = time_static.ci_app_private_key_rotated_at.rfc3339
    TF_VAR_changelog_app_private_key_rotated_at     = time_static.changelog_app_private_key_rotated_at.rfc3339
    TF_VAR_terraform_app_private_key_rotated_at     = time_static.terraform_app_private_key_rotated_at.rfc3339
    TF_VAR_oidc_exchange_client_secret_rotated_at   = time_static.oidc_exchange_client_secret_rotated_at.rfc3339

  }
}
