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
  #
  # `oci-alarms` removed 2026-09-20: the workspace it backed was retired
  # (no oci-alarms/ directory in tnoff/terraform, no alarm/notification-topic
  # resource anywhere in that repo). Removing it here on the next apply
  # destroys the terraform_state_buckets/oci_identity_policy resources for
  # it -- the bucket itself must be emptied first (OCI object storage has no
  # force_destroy; a non-empty bucket fails to delete).
  default = ["discord", "infra", "oci", "bootstrap", "apps", "dns"]
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
# External Secrets — admin/ holds these and pushes them to `terraform`'s
# GitHub Actions secrets and GitLab CI/CD variables (see terraform_ci_vars in
# main.tf). Manually rotated by editing this stack's tfvars (or env vars) and
# re-applying.
#
# Exception: discord_bot_token is NOT pushed anywhere from here -- see its
# description. It's still an external secret admin/ holds and tracks rotation
# for, just not one `terraform` consumes.
# ==============================================================================

variable "cloudflare_api_token" {
  description = "Cloudflare account API token used by terraform/dns's own cloudflare provider to manage DNS A records (tyler-north.com, castrovalleymirror.com, eastbaymassageandlymph.com). Terraform-only -- never reaches docker-apps or the cluster. See cloudflare_dns01_token for the separate token cert-manager's DNS01 solver uses, and terraform-admin/AGENTS.md's \"Two Discord bot tokens, not one\" for why these split the same way discord_token did: sharing one Cloudflare token between a human-run terraform apply and an in-cluster automated controller was already the pre-existing state (both used the same value, just via different sync paths), and this stops widening the same gap that broke Discord."
  type        = string
  sensitive   = true
}

variable "cloudflare_dns01_token" {
  description = "Cloudflare API token for cert-manager's DNS01 ACME solver -- a separate Cloudflare API token from cloudflare_api_token, scoped to the same zones (Zone:DNS:Edit + Zone:Zone:Read; Cloudflare tokens don't scope down to TXT-records-only). Pushed to terraform's CI and consumed by apps/'s kubernetes_secret_v1.cloudflare_api_key, which creates the cloudflare-api-key Secret in the cert-manager namespace directly -- same discord_bot_token pattern, chosen deliberately after that incident rather than reusing cloudflare_api_token for the cluster-facing copy."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account identifier (not secret)"
  type        = string
}

variable "discord_bot_token" {
  description = "The application bot's own Discord token -- the credential that runs as the live bot in docker-apps (role vidya-game-machine). Pushed to terraform's CI and consumed for real by apps/'s kubernetes_secret_v1.discord_bot_token, which creates the discord-bot-token Secret docker-apps' bot and dispatcher deployments read directly -- rotation no longer needs a manual re-seal of a docker-apps SealedSecret. (It briefly did NOT flow to CI, between the discord_management_token split and this incident: docker-apps/apps/discord/secrets-conf.yaml still hand-sealed DISCORD_TOKEN during that window, went stale on the next rotation, and crash-looped the bot. See AGENTS.md.)"
  type        = string
  sensitive   = true
}

variable "discord_management_token" {
  description = "Token for a SEPARATE Discord bot application, used only by terraform/discord's `discord` provider to manage server structure (roles, channels, webhooks). Distinct from discord_bot_token on purpose: that one is the live application bot's own identity, and reusing it for Terraform's provider auth was the thing this variable split away from. Needs its own bot application created in the Discord Developer Portal, invited to the server with the permissions terraform/discord's resources require (at minimum Manage Roles, Manage Channels, Manage Webhooks) -- there is no API to mint a second token for an existing bot."
  type        = string
  sensitive   = true
}

variable "openweather_api_key" {
  description = "Free-tier OpenWeather API key, shared by all three MagicMirror sites. Pushed to terraform's CI and consumed by apps/'s kubernetes_secret_v1.openweather_api_key, which creates the mirror-openweather-key Secret in each of the mirror-sanjose/mirror-castro/mirror-concord namespaces directly -- previously hand-sealed into each site's mirror-api-keys SealedSecret (docker-apps), a triple-seal-on-rotation risk in the same shape as discord_bot_token, just caught before an incident rather than after one. See docs/projects/sealed-secrets-terraform-admin-migration.md. See bart_api_key below for the same treatment applied to castro/concord's other mirror-api-keys entry."
  type        = string
  sensitive   = true
}

variable "bart_api_key" {
  description = "Free-tier 511.org transit token (BART's own GTFS-RT feed needs no key; this is what MMM-BartTimes' apiKey config field actually authenticates against 511 with), shared by the mirror-castro/mirror-concord sites. Pushed to terraform's CI and consumed by apps/'s kubernetes_secret_v1.bart_api_key, which creates the mirror-bart-key Secret in each of those two namespaces directly -- previously hand-sealed as BART_API_KEY in each site's mirror-api-keys SealedSecret (docker-apps) alongside OPENWEATHER_API_KEY, a dual-seal-on-rotation risk in the same shape openweather_api_key above was corrected for; this variable closes the same gap for the key that shared its SealedSecret. See docs/projects/sealed-secrets-terraform-admin-migration.md."
  type        = string
  sensitive   = true
}

# ==============================================================================
# discord's Spotify/YouTube search providers + VPN tunnel key, and eastbay's
# website secrets -- the project's scope widened 2026-09-21 from "match an
# existing terraform-admin variable" to "get every hand-sealed SealedSecret
# out of discord/eastbay," full stop. These nine were previously left sealed
# because none had a terraform-admin variable *yet* and none fanned out
# across multiple namespaces -- both true, but no longer the bar. Pushed to
# terraform's CI and consumed by apps/'s kubernetes_secret_v1.discord_search_creds,
# kubernetes_secret_v1.discord_vpn_key, and kubernetes_secret_v1.eastbay_website_creds,
# which create discord-search-creds/discord-vpn-key/eastbay-website-creds
# directly -- discord-conf-secrets, vpn-secrets, and eastbaymassage's
# website-secrets (docker-apps) are removed entirely, not left half-sealed.
# See docs/projects/sealed-secrets-terraform-admin-migration.md.
# ==============================================================================

variable "discord_spotify_client_id" {
  description = "Spotify application client ID, used by discord's search tier (and the bot/broker/downloader, which mirror its secret set) to resolve Spotify track/playlist URLs. Register an app at developer.spotify.com/dashboard. Consumed by apps/'s kubernetes_secret_v1.discord_search_creds."
  type        = string
  sensitive   = true
}

variable "discord_spotify_client_secret" {
  description = "Spotify application client secret, paired with discord_spotify_client_id. Consumed by apps/'s kubernetes_secret_v1.discord_search_creds."
  type        = string
  sensitive   = true
}

variable "discord_youtube_api_key" {
  description = "YouTube Data API key, used by discord's search tier (and the bot/broker/downloader) to resolve YouTube URLs and run searches. From console.cloud.google.com (YouTube Data API v3, API key credential). Consumed by apps/'s kubernetes_secret_v1.discord_search_creds."
  type        = string
  sensitive   = true
}

variable "discord_vpn_private_key" {
  description = "WireGuard private key for the Mullvad VPN tunnel the downloader's gluetun sidecar runs its per-download SOCKS5 exits through (docs corpus project_discord_vpn_exit_attribution). Self-generated, not vendor-issued -- Mullvad only ever receives the public half when the device is registered. Consumed by apps/'s kubernetes_secret_v1.discord_vpn_key."
  type        = string
  sensitive   = true
}

variable "eastbay_contact_email" {
  description = "Contact email address shown on the EastbayMassageAndLymph website. Not secret in the confidentiality sense (it's public-facing business info), sealed alongside the site's real secrets historically -- kept sensitive here for consistency with the rest of website-secrets, not because it needs protecting. Consumed by apps/'s kubernetes_secret_v1.eastbay_website_creds."
  type        = string
  sensitive   = true
}

variable "eastbay_contact_number" {
  description = "Contact phone number shown on the EastbayMassageAndLymph website. Same non-secret-but-bundled reasoning as eastbay_contact_email. Consumed by apps/'s kubernetes_secret_v1.eastbay_website_creds."
  type        = string
  sensitive   = true
}

variable "eastbay_email_host_user" {
  description = "SMTP username the EastbayMassageAndLymph website authenticates with to send contact-form email. Consumed by apps/'s kubernetes_secret_v1.eastbay_website_creds."
  type        = string
  sensitive   = true
}

variable "eastbay_email_host_password" {
  description = "SMTP password/app-password paired with eastbay_email_host_user. Consumed by apps/'s kubernetes_secret_v1.eastbay_website_creds."
  type        = string
  sensitive   = true
}

variable "eastbay_flask_secret_key" {
  description = "Flask session-signing secret for the EastbayMassageAndLymph website. Self-generated (e.g. python -c 'import secrets; print(secrets.token_hex(32))'), not vendor-issued -- there's no external dashboard value, just a random value the operator picks. Consumed by apps/'s kubernetes_secret_v1.eastbay_website_creds."
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

variable "ssh_public_key" {
  description = "SSH public key for OKE worker nodes"
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

