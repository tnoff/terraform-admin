locals {
  # The values tnoff/terraform's CI is allowed to know, all sourced from
  # admin's own inputs / outputs. Pushed to GitHub only (below); the GitLab
  # mirror gets none of them.
  terraform_ci_vars = {
    # No admin OCI key here any more (tnoff/terraform#135): every CI job now runs
    # as a federated (OIDC) identity or a scoped user below. The admin key stays
    # in .envrc for local operator runs only. The tenancy OCID is not a secret
    # and the OIDC login needs it to build its session profile.
    OCI_TENANCY_OCID = var.oci_tenancy_ocid

    # The state buckets' Object Storage namespace, for terraform's root.hcl backend
    # and remote_state reads. A GitHub variable, not a secret: see
    # terraform_github_public.
    OCI_NAMESPACE = data.oci_objectstorage_namespace.this.namespace

    TF_VAR_oci_tenancy_ocid = var.oci_tenancy_ocid

    # The runtime secrets vault, for oci/'s eso-reader policy (tnoff/terraform#341). An OCID, not a secret.
    TF_VAR_runtime_secrets_vault_ocid = module.runtime_secrets_vault.vault.id

    # The GitHub OIDC token-exchange app (tnoff/terraform#135, oidc-exchange.tf). Not
    # OCI_*-prefixed, so the terragrunt action does not export it to the job's
    # environment: the login action takes it as an input. The secret is only useful
    # together with a GitHub token the trust accepts.
    OIDC_EXCHANGE_DOMAIN_URL    = local.oidc_domain_endpoint
    OIDC_EXCHANGE_CLIENT_ID     = oci_identity_domains_app.oidc_exchange.name
    OIDC_EXCHANGE_CLIENT_SECRET = oci_identity_domains_app.oidc_exchange.client_secret

    # The same exchange values as TF_VAR_*, for terraform's infra/ stack to hand to the
    # image repos whose releases push to OCIR without a stored token (oci/ocir-pushers.tf in tnoff/terraform).
    # Only infra declares these variables, so only infra's job receives them.
    TF_VAR_oidc_exchange_domain_url    = local.oidc_domain_endpoint
    TF_VAR_oidc_exchange_client_id     = oci_identity_domains_app.oidc_exchange.name
    TF_VAR_oidc_exchange_client_secret = oci_identity_domains_app.oidc_exchange.client_secret

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

    # See admin_secrets_bundle for the rationale on the rotated_at
    # values — same source, different consumer (CI vs local .envrc).
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
      # survive. Running GitLab CI again would also need its CI variables,
      # which this stack no longer writes there.
      active = false
    }
  }
}
