<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_github"></a> [github](#requirement\_github) | ~> 6.0 |
| <a name="requirement_gitlab"></a> [gitlab](#requirement\_gitlab) | ~> 19.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.0 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | ~> 9.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~> 0.14 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_github"></a> [github](#provider\_github) | ~> 6.0 |
| <a name="provider_gitlab"></a> [gitlab](#provider\_gitlab) | ~> 19.0 |
| <a name="provider_local"></a> [local](#provider\_local) | ~> 2.0 |
| <a name="provider_oci"></a> [oci](#provider\_oci) | ~> 9.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |
| <a name="provider_time"></a> [time](#provider\_time) | ~> 0.14 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | ~> 4.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_terraform_gitlab"></a> [terraform\_gitlab](#module\_terraform\_gitlab) | git::https://github.com/tnoff/terraform-modules.git//gitlab/repo | f674402180cd49f2a76c1e2b9a77128efc497af9 |
| <a name="module_terraform_repo"></a> [terraform\_repo](#module\_terraform\_repo) | git::https://github.com/tnoff/terraform-modules.git//github/repo | f674402180cd49f2a76c1e2b9a77128efc497af9 |
| <a name="module_terraform_state_buckets"></a> [terraform\_state\_buckets](#module\_terraform\_state\_buckets) | git::https://github.com/tnoff/terraform-modules.git//oci/object-storage-bucket | f674402180cd49f2a76c1e2b9a77128efc497af9 |
| <a name="module_terraform_state_vault"></a> [terraform\_state\_vault](#module\_terraform\_state\_vault) | git::https://github.com/tnoff/terraform-modules.git//oci/secret-vault | f674402180cd49f2a76c1e2b9a77128efc497af9 |

## Resources

| Name | Type |
| ---- | ---- |
| [github_actions_secret.terraform](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) | resource |
| [github_actions_variable.terraform](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [local_sensitive_file.envrc](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [local_sensitive_file.mcp_readonly_oci_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [local_sensitive_file.mcp_readonly_private_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [local_sensitive_file.terraform_admin_private_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [oci_identity_api_key.mcp_readonly](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_api_key) | resource |
| [oci_identity_api_key.terraform_admin](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_api_key) | resource |
| [oci_identity_group.mcp_readonly](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_group) | resource |
| [oci_identity_group.terraform_admin](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_group) | resource |
| [oci_identity_policy.admin_kms_object_storage](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_policy) | resource |
| [oci_identity_policy.mcp_readonly](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_policy) | resource |
| [oci_identity_policy.terraform_admin](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_policy) | resource |
| [oci_identity_user.mcp_readonly](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user) | resource |
| [oci_identity_user.terraform_admin](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user) | resource |
| [oci_identity_user_group_membership.mcp_readonly](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user_group_membership) | resource |
| [oci_identity_user_group_membership.terraform_admin](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_user_group_membership) | resource |
| [terraform_data.backstage_app_private_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.bart_api_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.ci_app_private_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.cloudflare_api_token_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.cloudflare_dns01_token_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.discord_bot_token_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.discord_management_token_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.discord_spotify_client_id_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.discord_spotify_client_secret_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.discord_vpn_private_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.discord_youtube_api_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.eastbay_contact_email_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.eastbay_contact_number_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.eastbay_email_host_password_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.eastbay_email_host_user_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.eastbay_flask_secret_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.flux_app_private_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.gitlab_api_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.gitlab_ci_api_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.grafana_admin_password_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.grafana_admin_user_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.openweather_api_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.ssh_public_key_version](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [time_static.backstage_app_private_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.bart_api_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.ci_app_private_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.cloudflare_api_token_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.cloudflare_dns01_token_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.discord_bot_token_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.discord_management_token_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.discord_spotify_client_id_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.discord_spotify_client_secret_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.discord_vpn_private_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.discord_youtube_api_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.eastbay_contact_email_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.eastbay_contact_number_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.eastbay_email_host_password_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.eastbay_email_host_user_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.eastbay_flask_secret_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.flux_app_private_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.gitlab_api_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.gitlab_ci_api_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.grafana_admin_password_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.grafana_admin_user_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.openweather_api_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [time_static.ssh_public_key_rotated_at](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [tls_private_key.mcp_readonly](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.terraform_admin](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [gitlab_group.personal](https://registry.terraform.io/providers/gitlabhq/gitlab/latest/docs/data-sources/group) | data source |
| [oci_identity_tenancy.current](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_tenancy) | data source |
| [oci_objectstorage_namespace.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/objectstorage_namespace) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_backstage_app_client_id"></a> [backstage\_app\_client\_id](#input\_backstage\_app\_client\_id) | Client ID of the tnoff-backstage GitHub App (Iv23li... form). Not a secret, and shown on the App settings page without generating anything. Backstage requires the key to be PRESENT (readGithubIntegrationConfig uses getString, not getOptionalString) but never uses it: SingleInstanceGithubCredentialsProvider builds its auth config from appId + privateKey alone. Supplied so config parsing succeeds. | `string` | n/a | yes |
| <a name="input_backstage_app_id"></a> [backstage\_app\_id](#input\_backstage\_app\_id) | App ID of the tnoff-backstage GitHub App. Not a secret. From https://github.com/settings/apps/tnoff-backstage. | `number` | n/a | yes |
| <a name="input_backstage_app_private_key_b64"></a> [backstage\_app\_private\_key\_b64](#input\_backstage\_app\_private\_key\_b64) | Base64 of the tnoff-backstage App private key PEM, single line. Base64 for the same reason ci\_app\_private\_key\_b64 is: a multi-line PEM does not survive a shell round-trip cleanly. Produce with `base64 -w0 tnoff-backstage.*.private-key.pem`. Set in admin/terraform.tfvars (gitignored); apps/ base64decodes it into the Secret the pod mounts. | `string` | n/a | yes |
| <a name="input_bart_api_key"></a> [bart\_api\_key](#input\_bart\_api\_key) | Free-tier 511.org transit token (BART's own GTFS-RT feed needs no key; this is what MMM-BartTimes' apiKey config field actually authenticates against 511 with), shared by the mirror-castro/mirror-concord sites. Pushed to terraform's CI and consumed by apps/'s kubernetes\_secret\_v1.bart\_api\_key, which creates the mirror-bart-key Secret in each of those two namespaces directly -- previously hand-sealed as BART\_API\_KEY in each site's mirror-api-keys SealedSecret (docker-apps) alongside OPENWEATHER\_API\_KEY, a dual-seal-on-rotation risk in the same shape openweather\_api\_key above was corrected for; this variable closes the same gap for the key that shared its SealedSecret. See docs/projects/sealed-secrets-terraform-admin-migration.md. | `string` | n/a | yes |
| <a name="input_ci_app_client_id"></a> [ci\_app\_client\_id](#input\_ci\_app\_client\_id) | Client ID of the tnoff-ci GitHub App (Iv23li... form). Distinct from ci\_app\_id: actions/create-github-app-token deprecated its `app-id` input in favour of `client-id`, while the ruleset bypass actor still keys on the numeric App ID. Both are needed. Not a secret. | `string` | n/a | yes |
| <a name="input_ci_app_id"></a> [ci\_app\_id](#input\_ci\_app\_id) | App ID of the tnoff-ci GitHub App. Exported so terraform/infra can name it as a ruleset bypass actor (actor\_type Integration) and mint installation tokens in CI, replacing the human admin PAT that assemble-changelog needs to push to a protected default branch. Not a secret. | `number` | n/a | yes |
| <a name="input_ci_app_private_key_b64"></a> [ci\_app\_private\_key\_b64](#input\_ci\_app\_private\_key\_b64) | Base64 of the tnoff-ci GitHub App private key PEM, single line. Base64 rather than the raw PEM for the same reason OCI\_API\_KEY\_B64 is: GitLab can only mask a single-line value, so a multi-line PEM would have to travel through CI unmasked. Produce with `base64 -w0 tnoff-ci.private-key.pem`; terraform/infra base64decodes it when writing the Actions secret. | `string` | n/a | yes |
| <a name="input_cloudflare_account_id"></a> [cloudflare\_account\_id](#input\_cloudflare\_account\_id) | Cloudflare account identifier (not secret) | `string` | n/a | yes |
| <a name="input_cloudflare_api_token"></a> [cloudflare\_api\_token](#input\_cloudflare\_api\_token) | Cloudflare account API token used by terraform/dns's own cloudflare provider to manage DNS A records (tyler-north.com, castrovalleymirror.com, eastbaymassageandlymph.com). Terraform-only -- never reaches docker-apps or the cluster. See cloudflare\_dns01\_token for the separate token cert-manager's DNS01 solver uses, and terraform-admin/AGENTS.md's "Two Discord bot tokens, not one" for why these split the same way discord\_token did: sharing one Cloudflare token between a human-run terraform apply and an in-cluster automated controller was already the pre-existing state (both used the same value, just via different sync paths), and this stops widening the same gap that broke Discord. | `string` | n/a | yes |
| <a name="input_cloudflare_dns01_token"></a> [cloudflare\_dns01\_token](#input\_cloudflare\_dns01\_token) | Cloudflare API token for cert-manager's DNS01 ACME solver -- a separate Cloudflare API token from cloudflare\_api\_token, scoped to the same zones (Zone:DNS:Edit + Zone:Zone:Read; Cloudflare tokens don't scope down to TXT-records-only). Pushed to terraform's CI and consumed by apps/'s kubernetes\_secret\_v1.cloudflare\_api\_key, which creates the cloudflare-api-key Secret in the cert-manager namespace directly -- same discord\_bot\_token pattern, chosen deliberately after that incident rather than reusing cloudflare\_api\_token for the cluster-facing copy. | `string` | n/a | yes |
| <a name="input_config_file_profile"></a> [config\_file\_profile](#input\_config\_file\_profile) | Profile name in ~/.oci/config file | `string` | `"DEFAULT"` | no |
| <a name="input_discord_bot_token"></a> [discord\_bot\_token](#input\_discord\_bot\_token) | The application bot's own Discord token -- the credential that runs as the live bot in docker-apps (role vidya-game-machine). Pushed to terraform's CI and consumed for real by apps/'s kubernetes\_secret\_v1.discord\_bot\_token, which creates the discord-bot-token Secret docker-apps' bot and dispatcher deployments read directly -- rotation no longer needs a manual re-seal of a docker-apps SealedSecret. (It briefly did NOT flow to CI, between the discord\_management\_token split and this incident: docker-apps/apps/discord/secrets-conf.yaml still hand-sealed DISCORD\_TOKEN during that window, went stale on the next rotation, and crash-looped the bot. See AGENTS.md.) | `string` | n/a | yes |
| <a name="input_discord_management_token"></a> [discord\_management\_token](#input\_discord\_management\_token) | Token for a SEPARATE Discord bot application, used only by terraform/discord's `discord` provider to manage server structure (roles, channels, webhooks). Distinct from discord\_bot\_token on purpose: that one is the live application bot's own identity, and reusing it for Terraform's provider auth was the thing this variable split away from. Needs its own bot application created in the Discord Developer Portal, invited to the server with the permissions terraform/discord's resources require (at minimum Manage Roles, Manage Channels, Manage Webhooks) -- there is no API to mint a second token for an existing bot. | `string` | n/a | yes |
| <a name="input_discord_spotify_client_id"></a> [discord\_spotify\_client\_id](#input\_discord\_spotify\_client\_id) | Spotify application client ID, used by discord's search tier (and the bot/broker/downloader, which mirror its secret set) to resolve Spotify track/playlist URLs. Register an app at developer.spotify.com/dashboard. Consumed by apps/'s kubernetes\_secret\_v1.discord\_search\_creds. | `string` | n/a | yes |
| <a name="input_discord_spotify_client_secret"></a> [discord\_spotify\_client\_secret](#input\_discord\_spotify\_client\_secret) | Spotify application client secret, paired with discord\_spotify\_client\_id. Consumed by apps/'s kubernetes\_secret\_v1.discord\_search\_creds. | `string` | n/a | yes |
| <a name="input_discord_vpn_private_key"></a> [discord\_vpn\_private\_key](#input\_discord\_vpn\_private\_key) | WireGuard private key for the Mullvad VPN tunnel the downloader's gluetun sidecar runs its per-download SOCKS5 exits through (docs corpus project\_discord\_vpn\_exit\_attribution). Self-generated, not vendor-issued -- Mullvad only ever receives the public half when the device is registered. Consumed by apps/'s kubernetes\_secret\_v1.discord\_vpn\_key. | `string` | n/a | yes |
| <a name="input_discord_youtube_api_key"></a> [discord\_youtube\_api\_key](#input\_discord\_youtube\_api\_key) | YouTube Data API key, used by discord's search tier (and the bot/broker/downloader) to resolve YouTube URLs and run searches. From console.cloud.google.com (YouTube Data API v3, API key credential). Consumed by apps/'s kubernetes\_secret\_v1.discord\_search\_creds. | `string` | n/a | yes |
| <a name="input_eastbay_contact_email"></a> [eastbay\_contact\_email](#input\_eastbay\_contact\_email) | Contact email address shown on the EastbayMassageAndLymph website. Not secret in the confidentiality sense (it's public-facing business info), sealed alongside the site's real secrets historically -- kept sensitive here for consistency with the rest of website-secrets, not because it needs protecting. Enter it plain -- main.tf base64-encodes it before pushing to CI (GitLab's masked-variable check rejects any value containing '@', which every email address has) and apps/'s kubernetes\_secret\_v1.eastbay\_website\_creds base64decode()s it back for the Secret. | `string` | n/a | yes |
| <a name="input_eastbay_contact_number"></a> [eastbay\_contact\_number](#input\_eastbay\_contact\_number) | Contact phone number shown on the EastbayMassageAndLymph website. Same non-secret-but-bundled reasoning as eastbay\_contact\_email. Enter it plain -- main.tf base64-encodes it before pushing to CI (a formatted phone number routinely fails GitLab's masked-variable charset check) and apps/'s kubernetes\_secret\_v1.eastbay\_website\_creds base64decode()s it back. | `string` | n/a | yes |
| <a name="input_eastbay_email_host_password"></a> [eastbay\_email\_host\_password](#input\_eastbay\_email\_host\_password) | SMTP password/app-password paired with eastbay\_email\_host\_user. Consumed by apps/'s kubernetes\_secret\_v1.eastbay\_website\_creds. | `string` | n/a | yes |
| <a name="input_eastbay_email_host_user"></a> [eastbay\_email\_host\_user](#input\_eastbay\_email\_host\_user) | SMTP username the EastbayMassageAndLymph website authenticates with to send contact-form email. Consumed by apps/'s kubernetes\_secret\_v1.eastbay\_website\_creds. | `string` | n/a | yes |
| <a name="input_eastbay_flask_secret_key"></a> [eastbay\_flask\_secret\_key](#input\_eastbay\_flask\_secret\_key) | Flask session-signing secret for the EastbayMassageAndLymph website. Self-generated (e.g. python -c 'import secrets; print(secrets.token\_hex(32))'), not vendor-issued -- there's no external dashboard value, just a random value the operator picks. Consumed by apps/'s kubernetes\_secret\_v1.eastbay\_website\_creds. | `string` | n/a | yes |
| <a name="input_flux_app_id"></a> [flux\_app\_id](#input\_flux\_app\_id) | App ID of the tnoff-flux GitHub App. Not a secret. From https://github.com/settings/apps/tnoff-flux. | `number` | n/a | yes |
| <a name="input_flux_app_installation_id"></a> [flux\_app\_installation\_id](#input\_flux\_app\_installation\_id) | Installation ID of the tnoff-flux App on tnoff/docker-apps -- the trailing number in https://github.com/settings/installations/<id>. Not a secret. Flux accepts githubAppInstallationOwner instead, but the ID has been supported since 2.5 and the owner form is newer, so the ID is the safer pin. | `number` | n/a | yes |
| <a name="input_flux_app_private_key_b64"></a> [flux\_app\_private\_key\_b64](#input\_flux\_app\_private\_key\_b64) | Base64 of the tnoff-flux App private key PEM, single line. Base64 for the same reason ci\_app\_private\_key\_b64 is: a multi-line PEM does not survive a shell round-trip cleanly. Produce with `base64 -w0 tnoff-flux.*.private-key.pem`. Set in admin/terraform.tfvars (gitignored); bootstrap base64decodes it into the Secret. | `string` | n/a | yes |
| <a name="input_gitlab_api_key"></a> [gitlab\_api\_key](#input\_gitlab\_api\_key) | GitLab personal access token for admin user | `string` | n/a | yes |
| <a name="input_gitlab_ci_api_key"></a> [gitlab\_ci\_api\_key](#input\_gitlab\_ci\_api\_key) | GitLab access token for the tnoff-ci service account (formerly the tnoff-robot user's PAT, and formerly named gitlab\_bot\_api\_key) | `string` | n/a | yes |
| <a name="input_gitlab_ci_service_account_id"></a> [gitlab\_ci\_service\_account\_id](#input\_gitlab\_ci\_service\_account\_id) | Numeric service\_account\_id (as a string) of the tnoff-ci GitLab group service account, created manually via the GitLab UI. Not a secret. | `string` | n/a | yes |
| <a name="input_grafana_admin_password"></a> [grafana\_admin\_password](#input\_grafana\_admin\_password) | Grafana's bootstrap admin password, base64-encoded (defensive -- GitLab's masked-variable check has already rejected two other values in this project for containing characters outside its charset; encoding sidesteps the question for whatever the operator picks). Consumed by apps/'s kubernetes\_secret\_v1.grafana\_admin, which base64decode()s it -- previously hand-sealed as grafana-admin's admin-password (docker-apps). Also read by monitoring/grafana-sa-bootstrap's Job. Changing this value does NOT change Grafana's actual live admin password -- see the variable block comment above. | `string` | n/a | yes |
| <a name="input_grafana_admin_user"></a> [grafana\_admin\_user](#input\_grafana\_admin\_user) | Grafana's bootstrap admin username, base64-encoded (GitLab's masked-variable check requires >= 8 chars; the conventional 'admin' is only 5). Consumed by apps/'s kubernetes\_secret\_v1.grafana\_admin, which base64decode()s it -- previously hand-sealed as grafana-admin's admin-user (docker-apps). Also read by monitoring/grafana-sa-bootstrap's Job to authenticate to Grafana's own REST API when minting service-account tokens -- see the Deployment/Job comments for why a rotation here doesn't propagate on its own. | `string` | n/a | yes |
| <a name="input_mcp_readonly_group_name"></a> [mcp\_readonly\_group\_name](#input\_mcp\_readonly\_group\_name) | Name of the tenancy-wide read-only group backing the local OCI MCP server | `string` | `"mcp-readonly-bot"` | no |
| <a name="input_mcp_readonly_private_key_path"></a> [mcp\_readonly\_private\_key\_path](#input\_mcp\_readonly\_private\_key\_path) | Path where the MCP read-only user's API key PEM will be written | `string` | `"generated-output/mcp_readonly_api_key.pem"` | no |
| <a name="input_mcp_readonly_user_name"></a> [mcp\_readonly\_user\_name](#input\_mcp\_readonly\_user\_name) | Name of the tenancy-wide read-only user backing the local OCI MCP server | `string` | `"mcp-readonly-bot"` | no |
| <a name="input_oci_region"></a> [oci\_region](#input\_oci\_region) | OCI region | `string` | `"us-ashburn-1"` | no |
| <a name="input_oci_tenancy_ocid"></a> [oci\_tenancy\_ocid](#input\_oci\_tenancy\_ocid) | OCID of the tenancy (all resources created in root compartment) | `string` | n/a | yes |
| <a name="input_openweather_api_key"></a> [openweather\_api\_key](#input\_openweather\_api\_key) | Free-tier OpenWeather API key, shared by all three MagicMirror sites. Pushed to terraform's CI and consumed by apps/'s kubernetes\_secret\_v1.openweather\_api\_key, which creates the mirror-openweather-key Secret in each of the mirror-sanjose/mirror-castro/mirror-concord namespaces directly -- previously hand-sealed into each site's mirror-api-keys SealedSecret (docker-apps), a triple-seal-on-rotation risk in the same shape as discord\_bot\_token, just caught before an incident rather than after one. See docs/projects/sealed-secrets-terraform-admin-migration.md. See bart\_api\_key below for the same treatment applied to castro/concord's other mirror-api-keys entry. | `string` | n/a | yes |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | SSH public key for OKE worker nodes | `string` | n/a | yes |
| <a name="input_state_bucket_prefix"></a> [state\_bucket\_prefix](#input\_state\_bucket\_prefix) | Prefix for state bucket names | `string` | `"terraform-state"` | no |
| <a name="input_terraform_admin_group_name"></a> [terraform\_admin\_group\_name](#input\_terraform\_admin\_group\_name) | Name of the Terraform admin group | `string` | `"terraform-administrators"` | no |
| <a name="input_terraform_admin_private_key_path"></a> [terraform\_admin\_private\_key\_path](#input\_terraform\_admin\_private\_key\_path) | Path where the Terraform admin private key will be saved | `string` | `"generated-output/terraform_admin_private_key.pem"` | no |
| <a name="input_terraform_admin_user_name"></a> [terraform\_admin\_user\_name](#input\_terraform\_admin\_user\_name) | Name of the Terraform admin user for infrastructure management | `string` | `"terraform-admin"` | no |
| <a name="input_terraform_app_id"></a> [terraform\_app\_id](#input\_terraform\_app\_id) | App ID of the tnoff-terraform GitHub App. Not a secret. From https://github.com/settings/apps/tnoff-terraform. | `number` | n/a | yes |
| <a name="input_terraform_app_installation_id"></a> [terraform\_app\_installation\_id](#input\_terraform\_app\_installation\_id) | Installation ID of the tnoff-terraform App on this account -- the trailing number in https://github.com/settings/installations/<id>. Not a secret. | `number` | n/a | yes |
| <a name="input_terraform_app_private_key_b64"></a> [terraform\_app\_private\_key\_b64](#input\_terraform\_app\_private\_key\_b64) | Base64 of the tnoff-terraform App private key PEM, single line. Produce with `base64 -w0 tnoff-terraform.*.private-key.pem`. Set in admin/terraform.tfvars (gitignored); terraform/infra base64decodes it for the provider's app\_auth block. | `string` | n/a | yes |
| <a name="input_vault_name"></a> [vault\_name](#input\_vault\_name) | Name prefix for the vault and KMS key | `string` | `"terraform-state"` | no |
| <a name="input_workspaces"></a> [workspaces](#input\_workspaces) | List of workspace names to create state buckets for (admin state stays local) | `list(string)` | <pre>[<br/>  "discord",<br/>  "infra",<br/>  "oci",<br/>  "bootstrap",<br/>  "apps",<br/>  "dns"<br/>]</pre> | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->