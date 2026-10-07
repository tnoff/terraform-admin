# Secret rotation

Runbook for rotating the credentials this stack holds or originates. The
authoritative list is `variables.tf` (inputs), `rotation-tracking.tf`
(which inputs get a rotation timestamp) and this repo's `catalog-info.yaml`
(one Backstage `Resource` per credential, with its source variable and
consumers; metadata only, never values). Start there if a name below does not
match.

Credentials fall into four classes, each with its own procedure:

| Class | Examples | Rotated by |
|---|---|---|
| [Operator-rotated secrets](#operator-rotated-secrets) | Discord tokens, Cloudflare tokens, vendor API keys, GitLab tokens, Grafana admin | Mint at the vendor, edit the input, re-apply this stack |
| [GitHub App private keys](#github-app-private-keys) | `tnoff-terraform`, `tnoff-ci`, `tnoff-flux`, `tnoff-backstage` | New key in the App settings, edit the input, re-apply |
| [OCI keys generated here](#oci-keys-generated-by-this-stack) | `terraform-admin`, `mcp-readonly-bot` | `terraform apply -replace` |
| [Slot-managed credentials](#credentials-rotated-elsewhere) | OCI auth tokens, S3 keys, scanner API keys, Discord webhooks | Generation flags in the `terraform` repo |

## How a rotation reaches consumers

1. You change an input and `terraform apply` here (locally; this stack is
   never applied by CI).
2. The apply rewrites the values pushed to the `terraform` repo's GitHub
   Actions secrets and variables (`TF_VAR_*`, plus `OCI_*`), and regenerates
   `generated-output/.envrc`. See [infra-bootstrap.md](infra-bootstrap.md) for
   the mechanism.
3. For an operator-rotated input, `rotation-tracking.tf` replaces the matching
   `terraform_data.<name>_version` (its trigger is the sha256 of the value) and
   so re-stamps `time_static.<name>_rotated_at`. That timestamp travels as
   `TF_VAR_<name>_rotated_at` into the `layer-1-rotation-ledger` ConfigMap and
   the `secret-age-tracker.tnoff/last-rotated` annotations that the
   secret-age tracker reads. No manual bookkeeping is needed.
4. The workload stacks pick the new value up only when they next **apply**.
   `terraform`'s `apply.yml` runs a stack only if files under that stack's
   directory changed (or repo-wide files such as `root.hcl`, `ci/` or
   `.github/` changed), so a rotation that does not touch `apps/` or `infra/`
   does not re-render anything. Land a trivial change under the consuming
   stack (a comment on the relevant resource) so CI applies it.
5. In-cluster consumers read a Secret as an environment variable, so the pod
   must restart to see it. Deployments annotated for Reloader roll on their
   own; otherwise `kubectl rollout restart`.

Run applies from a clean checkout of `main`. Back up the local state file
first if you are changing anything destructive.

## Operator-rotated secrets

Every variable below is an input (set it via `TF_VAR_<name>` or a gitignored
`terraform.tfvars`), pushed to `terraform`'s CI, and rotation-tracked. The
consumer column names the stack that renders it.

| Input | Source | Consumer |
|---|---|---|
| `discord_bot_token` | Discord developer portal, live application bot | `apps/` -> `discord-bot-token` Secret |
| `discord_management_token` | Discord developer portal, separate bot application | `discord/` provider (CI only) |
| `cloudflare_api_token` | Cloudflare dashboard, DNS provider token | `dns/` provider (CI only) |
| `cloudflare_dns01_token` | Cloudflare dashboard, separate zone-scoped token | `apps/` -> `cloudflare-api-key` Secret (cert-manager) |
| `openweather_api_key`, `bart_api_key` | OpenWeather; 511.org | `apps/` -> `mirror-*-key` Secrets in each mirror namespace |
| `discord_spotify_client_id`, `discord_spotify_client_secret`, `discord_youtube_api_key` | Spotify dashboard; Google Cloud console | `apps/` -> `discord-search-creds` |
| `discord_vpn_private_key` | Self-generated WireGuard key (Mullvad holds only the public half) | `apps/` -> `discord-vpn-key` |
| `eastbay_contact_email`, `eastbay_contact_number`, `eastbay_email_host_user`, `eastbay_email_host_password`, `eastbay_flask_secret_key` | Business details; SMTP account; `python -c 'import secrets; print(secrets.token_hex(32))'` | `apps/` -> `eastbay-website-creds` |
| `grafana_admin_user`, `grafana_admin_password` | Chosen by the operator | `apps/` -> `grafana-admin-creds` (see caveat) |
| `backstage_mcp_token` | `openssl rand -hex 24` | `apps/` -> `backstage-mcp-token` |
| `hathor_vpn_private_key`, `hathor_vpn_addresses` | A **new** Mullvad WireGuard device (mullvad.net/en/account/wireguard-config; never the discord device's): `PrivateKey` and `Address` from the same file. Replace both together | `apps/` -> `hathor-vpn-key` |
| `hathor_url_token` | `openssl rand -hex 32`. The only auth on the hathor endpoint; rotate on any leak | `apps/` -> `hathor-url-token` |
| `hathor_google_api_key`, `hathor_twitch_client_id`, `hathor_twitch_client_secret` | Google Cloud console (YouTube Data API v3); dev.twitch.tv console | `apps/` -> `hathor-api-keys` |
| `hathor_youtube_cookies_b64` | `base64 -w0 cookies.txt` (Netscape format, e.g. exported from a logged-in browser). Expires; replace regularly | `apps/` -> `hathor-youtube-cookies` |
| `gitlab_api_key`, `gitlab_ci_api_key` | GitLab personal access token (admin user); token for the `tnoff-ci` service account | `infra/` GitLab provider and mirror token (CI only) |
| `ssh_public_key` | `ssh-keygen` | `oci/` OKE node cloud-init |

Procedure:

1. Mint the new value at its source.
2. Set the new value in your private env file (or the matching `TF_VAR_*`) and
   re-source it.
3. `terraform plan` in this repo. Expect the `terraform_data.<name>_version`
   and `time_static.<name>_rotated_at` for that input to be replaced, and
   the corresponding `github_actions_secret.terraform["TF_VAR_<name>"]` to
   update in place. Then `terraform apply`.
4. Confirm it landed: `gh secret list --repo tnoff/terraform` shows a fresh
   *updated* time for `TF_VAR_<name>`, and
   `gh variable get TF_VAR_<name>_rotated_at --repo tnoff/terraform` shows
   today (the timestamps are public variables, not secrets).
5. Land a trivial change under the consuming stack's directory (see
   [How a rotation reaches consumers](#how-a-rotation-reaches-consumers)) and
   confirm `apply:<stack>` succeeded.
6. Restart in-cluster consumers that do not roll via Reloader, then revoke the
   old value at its source.

Caveats:

- **Eastbay contact email and number** are entered plain. `main.tf`
  base64-encodes them before pushing, and `apps/` decodes them back.
- **Grafana admin credentials** are only read by Grafana when it first
  initialises its database. Changing them updates the Kubernetes Secret but
  not the live admin account; a real rotation also needs the Grafana UI, API or
  `grafana-cli`. The Secret deliberately carries no `last-rotated` annotation.
- **`ssh_public_key`** only affects newly created nodes. Existing nodes keep
  the old authorised key until the node pool is cycled (see the node pool cycle
  runbook in the docker-apps TechDocs).
- **`discord_bot_token` and `discord_management_token`** are two different bot
  applications; never point `terraform/discord` at the live bot's token, and
  never stop pushing `discord_bot_token` to CI (see
  [AGENTS.md](AGENTS.md#two-discord-bot-tokens-not-one)).

## GitHub App private keys

Four Apps, deliberately separate so each has its own blast radius.

| Input | App | Where it ends up |
|---|---|---|
| `terraform_app_private_key_b64` | `tnoff-terraform` (repo admin) | This stack's own GitHub provider; `terraform`'s CI (`infra/` provider) |
| `ci_app_private_key_b64` | `tnoff-ci` (Contents + Workflows write, ruleset bypass) | `CI_APP_PRIVATE_KEY` Actions secret in every repo |
| `flux_app_private_key_b64` | `tnoff-flux` (Contents read on `docker-apps`) | Operator-run `bootstrap/` only, never CI |
| `backstage_app_private_key_b64` | `tnoff-backstage` (Contents + Metadata read) | `apps/` -> `backstage-github-app-credentials` |

Procedure (all four):

1. In the App's settings (`https://github.com/settings/apps/<app>`) generate a
   new private key. Leave the old one active.
2. `base64 -w0 <downloaded>.pem` and set the matching `*_private_key_b64`
   input. Re-source, `terraform plan`, `terraform apply`.
3. Do the per-App step below, verify, then delete the old key in the App
   settings and shred the downloaded PEM.

Per-App steps:

- **`tnoff-terraform`:** the apply above updates `terraform`'s secret.
  Subsequent `infra/` runs authenticate with the new key. This App has no
  rotation timestamp in `rotation-tracking.tf`.
- **`tnoff-ci`:** `terraform_repo` here updates `terraform`'s copy. Every other
  repo's `CI_APP_PRIVATE_KEY` is written by `terraform/infra`, so land a
  change under `infra/` for it to re-apply. **This repo's own `CI_APP_*`
  secrets are hand-managed** (the bootstrap stack cannot own its own repo):

  ```bash
  gh secret set CI_APP_PRIVATE_KEY --repo tnoff/terraform-admin < key.pem
  ```
- **`tnoff-flux`:** apply `terraform/bootstrap` as the operator (live bastion
  tunnel plus `oci-kms` context); it rewrites the `flux-system-github-app`
  Secret. Check `flux get sources git flux-system` shows `Ready: True` with a
  recent update. Flux mints its own hourly tokens, so there is no expiry to
  chase.
- **`tnoff-backstage`:** land a change under `apps/`, then restart the Backstage
  Deployment if it does not roll.

## OCI keys generated by this stack

This stack generates RSA key pairs, registers the public half with OCI and
writes the private half to `generated-output/`.

| Key | Resource | Output |
|---|---|---|
| `terraform-admin` user | `tls_private_key.terraform_admin` | `generated-output/terraform_admin_private_key.pem`; `OCI_API_KEY_B64` and `OCI_FINGERPRINT` in CI and `.envrc` |
| `terraform-cluster-ci` user | `tls_private_key.cluster_ci` | `CLUSTER_CI_OCI_API_KEY_B64` and `CLUSTER_CI_OCI_FINGERPRINT` in CI only. The user OCID (`CLUSTER_CI_OCI_USER_OCID`, and `TF_VAR_cluster_ci_user_ocid` in `.envrc`) does not change on rotation |
| `terraform-dns-ci` user | `tls_private_key.dns_ci` | `DNS_CI_OCI_API_KEY_B64` and `DNS_CI_OCI_FINGERPRINT` in CI only. Same shape as `terraform-cluster-ci` |
| `terraform-infra-ci` and `terraform-discord-ci` users | `tls_private_key.state_ci["infra"]` / `["discord"]` | `INFRA_CI_OCI_*` / `DISCORD_CI_OCI_*` in CI only. Same shape as `terraform-cluster-ci` |
| `mcp-readonly-bot` user | `tls_private_key.mcp_readonly` | `generated-output/mcp_readonly_api_key.pem` and a ready-made `mcp_readonly_oci_config` profile |

Rotate with a targeted replace:

```bash
terraform apply -replace=tls_private_key.terraform_admin
terraform apply -replace=tls_private_key.mcp_readonly
terraform apply -replace=tls_private_key.cluster_ci
terraform apply -replace=tls_private_key.dns_ci
terraform apply -replace='tls_private_key.state_ci["infra"]'
terraform apply -replace='tls_private_key.state_ci["discord"]'
```

This is destroy-then-recreate, so there is a short window where the old key is
gone before the new one is live. For `terraform-admin`:

1. Make sure no `terraform` CI run is in flight.
2. Apply. The new fingerprint, PEM and `OCI_*` values are pushed to
   `terraform`'s Actions secrets in the same apply.
3. Re-source `generated-output/.envrc` in every shell and direnv session
   (`OCI_FINGERPRINT` changed).
4. Verify: `oci iam api-key list --user-id <terraform-admin-user-ocid>` shows
   one fresh key, and the next `terraform` CI run authenticates.

`terraform-cluster-ci` is the identity `terraform`'s `apps/` and `dns/` jobs use
(tnoff/terraform#116) and rotates the same way. Replacing its key leaves the
user OCID alone, so `bootstrap/`'s RBAC binding survives; only the next
`apply:apps` / `apply:dns` run needs the new `CLUSTER_CI_*` secrets, which the
same apply pushes.

For `mcp-readonly-bot`, afterwards paste the regenerated
`generated-output/mcp_readonly_oci_config` profile into `~/.oci/config`
(and see the local OCI MCP setup in mcp-local).

KMS keys are never rotated here: re-keying would invalidate every state bucket.

### Minting a personal OCI API key by hand

Only for your own CLI profile or a throwaway key; service-user keys must flow
through terraform (a hand-uploaded key drifts from state).

```bash
openssl genrsa -out ~/.oci/oci_api_key.pem 2048 && chmod 600 ~/.oci/oci_api_key.pem
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
# Fingerprint (matches the Console):
openssl rsa -pubout -outform DER -in ~/.oci/oci_api_key.pem 2>/dev/null \
  | openssl md5 -c | awk '{print $NF}'
```

Add the public key under User Settings -> API Keys in the Console, then set
`fingerprint=` and `key_file=` in `~/.oci/config`.

- The SDK's "append an extra line with `OCI_API_KEY`" warning is cosmetic.
  Silence it with `export SUPPRESS_LABEL_WARNING=True`, or append
  `OCI_API_KEY` as a line **after** the `-----END` footer of the private key
  only. Never label the public key: that changes its fingerprint.
- A new key can return `NotAuthenticated` for a call or two while IAM
  propagates it; do not re-mint on the first 401.

## Credentials rotated elsewhere

- **Slot-managed (zero downtime):** OCI auth tokens, customer secret (S3) keys,
  the scanner, monitoring-reader and autoscaler API keys, and Discord
  webhooks rotate through generation flags in the `terraform` repo. Follow its
  [generation-slot rotation runbook](https://github.com/tnoff/terraform/blob/main/docs/generation-slot-rotation.md);
  never `apply -replace` them.
- **Flux GitLab deploy token:** `terraform/infra/flux-deploy-token.tf` creates it
  and `bootstrap/` renders `flux-system-https` from it. Flux now syncs from
  GitHub with the `tnoff-flux` App, so this token is the rollback path. To
  rotate, set `var.flux_deploy_token_expires_at` (`infra/variables.tf`) to a
  new date, apply `infra/` (CI), then apply `bootstrap/` as the operator.
- **Grafana service-account tokens** are minted in-cluster by docker-apps'
  `grafana-sa-bootstrap` and are not terraform-managed.

## Cadence

There is no enforced schedule. The secret-age tracker reports each
credential's age from the timestamps and annotations described above; rotate
before it flags one, and immediately on suspected exposure.
