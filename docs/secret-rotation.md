# Secret rotation

Runbook for rotating the credentials this stack holds or originates. The
authoritative list is `variables.tf` (inputs), `rotation-tracking.tf`
(which inputs get a rotation timestamp) and this repo's `catalog-info.yaml`
(one Backstage `Resource` per credential, with its source variable and
consumers; metadata only, never values). Start there if a name below does not
match.

Credentials fall into five classes, each with its own procedure:

| Class | Examples | Rotated by |
|---|---|---|
| [Operator-rotated secrets](#operator-rotated-secrets) | Discord tokens, Cloudflare tokens, vendor API keys, GitLab tokens, Grafana admin | Mint at the vendor, edit the input, re-apply this stack |
| [GitHub App private keys](#github-app-private-keys) | `tnoff-terraform`, `tnoff-ci`, `tnoff-flux`, `tnoff-backstage` | New key in the App settings, edit the input, re-apply |
| [OCI keys generated here](#oci-keys-generated-by-this-stack) | `terraform-admin`, `mcp-readonly-bot` | `terraform apply -replace` |
| [Token-exchange apps](#token-exchange-apps) | `terraform-oidc-spike-exchange` (the in-cluster `k8s-workload-exchange` moved to tnoff/terraform) | Deactivate, then `apply -replace`, then apply `trust/` |
| [Slot-managed credentials](#credentials-rotated-elsewhere) | OCI API keys (`cluster-autoscaler`, `oidc-jwks-publisher`), the local dev S3 key, Discord webhooks | Generation flags in the `terraform` repo |

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
| `cloudflare_api_token` | Cloudflare dashboard, one token with Zone:DNS:Edit + Zone:Zone:Read on both zones | `dns/` provider (CI) and `apps/` -> `cloudflare-api-key` Secret (cert-manager). Verify with `tokens/verify` and a TXT write/delete before applying (see the Caveats below) |
| `openweather_api_key`, `bart_api_key` | OpenWeather; 511.org | `apps/` -> `mirror-*-key` Secrets in each mirror namespace |
| `five11_api_key` | 511.org (api.511.org token) | `apps/` -> `mirror-511-key` Secret in mirror-dublin and mirror-sanjose |
| `discord_spotify_client_id`, `discord_spotify_client_secret`, `discord_youtube_api_key` | Spotify dashboard; Google Cloud console | `apps/` -> `discord-search-creds` |
| `discord_vpn_private_key`, `discord_vpn_addresses` | Self-generated WireGuard key (Mullvad holds only the public half) and the `Address` (CIDR) Mullvad assigned to that device when the public half was registered; replace them together | `apps/` -> `discord-vpn-key` (`WIREGUARD_PRIVATE_KEY`, `WIREGUARD_ADDRESSES`) |
| `eastbay_contact_email`, `eastbay_contact_number`, `eastbay_email_host_user`, `eastbay_email_host_password`, `eastbay_flask_secret_key` | Business details; SMTP account; `python -c 'import secrets; print(secrets.token_hex(32))'` | `apps/` -> `eastbay-website-creds` |
| `grafana_admin_user`, `grafana_admin_password` | Chosen by the operator | `apps/` -> `grafana-admin-creds` (see caveat) |
| `backstage_mcp_token` | `openssl rand -hex 24` | `apps/` -> `backstage-mcp-token` |
| `hathor_vpn_private_key`, `hathor_vpn_addresses`, `hathor_vpn_server_hostnames` | A **new** Mullvad WireGuard device (mullvad.net/en/account/wireguard-config; never the discord device's): `PrivateKey` and `Address` from the same file, replaced together. The hostnames are a comma-separated list of Mullvad WireGuard servers that exist in gluetun's server list | `apps/` -> `hathor-vpn-key` |
| `hathor_url_token` | `openssl rand -hex 32`. The only auth on the hathor endpoint; rotate on any leak | `apps/` -> `hathor-url-token` |
| `hathor_google_api_key`, `hathor_twitch_client_id`, `hathor_twitch_client_secret` | Google Cloud console (YouTube Data API v3); dev.twitch.tv console | `apps/` -> `hathor-api-keys` |
| `hathor_youtube_cookies_b64` | A Netscape-format cookies file stripped to YouTube only (`scripts/filter_cookies.py cookies.txt --b64` in tnoff/docker-apps, which also prints the one-line base64; a raw browser export holds a login for every site). Expires; replace regularly | `apps/` -> `hathor-youtube-cookies` |
| `gitlab_api_key` | GitLab personal access token, scope `api` (admin user) | `infra/` GitLab provider (CI only) |
| *(none: `GITLAB_MIRROR_TOKEN`)* | Not an operator input. `terraform/infra` mints it for the `tnoff-ci` service account (`read_api` + `write_repository`, 90 days) and writes it to the `github-workflows` repo; it re-mints itself when an apply runs in its last 14 days. See [fleet-mirror](https://github.com/tnoff/github-workflows/blob/main/docs/fleet-mirror.md). Verify with `gh workflow run fleet-mirror.yml --repo tnoff/github-workflows -f dry_run=true` | `github-workflows` Actions secret |
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
   `gh variable list --repo tnoff/terraform --json name,value` (the `TF_VAR_<NAME>_ROTATED_AT` entry; `gh variable get` does not exist) shows
   today (the timestamps are public variables, not secrets).
5. Land a trivial change under the consuming stack's directory (see
   [How a rotation reaches consumers](#how-a-rotation-reaches-consumers)) and
   confirm `apply:<stack>` succeeded.
6. Restart in-cluster consumers that do not roll via Reloader, then revoke the
   old value at its source.

Caveats:

- **Eastbay contact email and number** are entered plain. `ci-vars.tf`
  base64-encodes them before pushing, and `apps/` decodes them back.
- **Grafana admin credentials** are only read by Grafana when it first
  initialises its database. Changing them updates the Kubernetes Secret but
  not the live admin account; a real rotation also needs the Grafana UI, API or
  `grafana-cli`. The Secret deliberately carries no `last-rotated` annotation.
- **`ssh_public_key`** only affects newly created nodes. Existing nodes keep
  the old authorised key until the node pool is cycled (see the node pool cycle
  runbook in the docker-apps TechDocs).
- **`cloudflare_api_token`** feeds both `terraform/dns` and cert-manager, and
  Let's Encrypt reuses a validated authorization for about 30 days, so a renewal
  will not exercise a new token on demand. Before step 3, and again after
  `apply:apps` and `apply:dns` are green, prove it against both zones. This
  writes one TXT record and deletes it; `TOKEN` is the new value:

  ```bash
  curl -s -H "Authorization: Bearer $TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify | jq '.result.status'   # "active"
  for Z in tyler-north.com eastbaymassageandlymph.com; do
    ZONE=$(curl -s -H "Authorization: Bearer $TOKEN" "https://api.cloudflare.com/client/v4/zones?name=$Z" | jq -r '.result[0].id')
    REC=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      "https://api.cloudflare.com/client/v4/zones/$ZONE/dns_records" \
      --data "{\"type\":\"TXT\",\"name\":\"_token-check.$Z\",\"content\":\"token-check\",\"ttl\":120}" | jq -r '.result.id')
    curl -s -X DELETE -H "Authorization: Bearer $TOKEN" "https://api.cloudflare.com/client/v4/zones/$ZONE/dns_records/$REC" | jq '.success'   # true
  done
  ```

  A failure at the zone step means Zone:Zone:Read is missing; at the record
  step, Zone:DNS:Edit.
- **`discord_bot_token` and `discord_management_token`** are two different bot
  applications; never point `terraform/discord` at the live bot's token, and
  never stop pushing `discord_bot_token` to CI (see
  [AGENTS.md](AGENTS.md#two-discord-bot-tokens-not-one)).

## GitHub App private keys

Six Apps, deliberately separate so each has its own blast radius.

| Input | App | Where it ends up |
|---|---|---|
| `terraform_app_private_key_b64` | `tnoff-terraform` (repo admin) | This stack's own GitHub provider; `terraform`'s CI (`infra/` provider) |
| `ci_app_private_key_b64` | `tnoff-ci` (Contents + Workflows write; installed on selected repos, not `terraform` or `terraform-admin`; no ruleset bypass) | `CI_APP_PRIVATE_KEY` Actions secret in every repo it is installed on |
| `changelog_app_private_key_b64` | changelog App (Contents write only; the only ruleset bypass actor) | `CHANGELOG_APP_PRIVATE_KEY` Actions secret on the repos that run `assemble-changelog` only |
| `flux_app_private_key_b64` | `tnoff-flux` (Contents read on `docker-apps`) | `bootstrap/`: the `.envrc` locally and the `bootstrap-plan` / `bootstrap-apply` Environment secrets in CI (never a repo-level secret) |
| `backstage_app_private_key_b64` | `tnoff-backstage` (Contents + Metadata read) | `apps/` -> `backstage-github-app-credentials` |

The sixth, the Renovate App for this repo only, is not an input here (the bootstrap stack cannot own its own repo): its `RENOVATE_APP_CLIENT_ID` and `RENOVATE_APP_PRIVATE_KEY` are hand-set secrets on `tnoff/terraform-admin`.

Procedure (the five above):

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
  change under `infra/` for it to re-apply. This repo has no `CI_APP_*`
  secrets: tnoff-ci is not installed here.
- **Renovate App (this repo only):** its `RENOVATE_APP_CLIENT_ID` and
  `RENOVATE_APP_PRIVATE_KEY` secrets are hand-managed (the bootstrap stack
  cannot own its own repo):

  ```bash
  gh secret set RENOVATE_APP_PRIVATE_KEY --repo tnoff/terraform-admin < key.pem
  ```
- **`tnoff-flux`:** apply this stack (it updates the Environment secrets), then run
  `terraform/bootstrap` (the CI `bootstrap` workflow, approving the apply); it rewrites the `flux-system-github-app`
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
| `terraform-admin` user | `tls_private_key.terraform_admin` | `generated-output/terraform_admin_private_key.pem`; `OCI_API_KEY_B64` and `OCI_FINGERPRINT` in `.envrc` only (CI holds no OCI key since tnoff/terraform#135: every job signs in with its GitHub OIDC token) |
| `mcp-readonly-bot` user | `tls_private_key.mcp_readonly` | `generated-output/mcp_readonly_api_key.pem` and a ready-made `mcp_readonly_oci_config` profile |

Rotate with a targeted replace:

```bash
terraform apply -replace=tls_private_key.terraform_admin
terraform apply -replace=tls_private_key.mcp_readonly
```

This is destroy-then-recreate, so there is a short window where the old key is
gone before the new one is live. For `terraform-admin`:

1. Make sure no `terraform` CI run is in flight.
2. Apply. The new fingerprint and PEM land in `.envrc`; they are no longer
   pushed to `terraform`'s Actions secrets (tnoff/terraform#135).
3. Re-source `generated-output/.envrc` in every shell and direnv session
   (`OCI_FINGERPRINT` changed).
4. Verify: `oci iam api-key list --user-id <terraform-admin-user-ocid>` shows
   one fresh key, and a local `bin/tf plan` authenticates.

The CI identities and the in-cluster workloads have no key to rotate; the one stored secret on each
path is a token-exchange app's client secret. See [Token-exchange apps](#token-exchange-apps).

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

## Token-exchange apps

The one confidential Identity Domains app this stack holds, `terraform-oidc-spike-exchange`
(`oidc-exchange.tf`), is CI's own login: its client id and secret are the `OIDC_EXCHANGE_*` Actions
secrets every `terraform` job uses to get an OCI token. The secret is useless on its own: an exchange
also needs a GitHub OIDC token the `github-actions-oidc-spike` trust (tnoff/terraform `trust/`)
accepts. It stays here, not in CI, because if CI replaced it every job would fail to log in until the
new secret reached GitHub, and CI could not repair itself.

The in-cluster app, `k8s-workload-exchange`, moved to tnoff/terraform `trust/` next to the trust that
lists it; its rotation runbook is in
[Rotating the exchange app](https://github.com/tnoff/terraform/blob/main/docs/k8s-workload-federation.md#rotating-the-exchange-app).

The secret is **not slot-managed**. A rotation replaces the app, so it has a gap: from the moment the
old app stops working until the new secret reaches GitHub *and* the trust lists the new client id, every
`terraform` job fails to log in. An active app cannot be deleted: Terraform's delete returned
`400-BadErrorResponse` with no message. Deactivate it first. Until the delete succeeds, reactivating it
is the rollback.

Never run `terraform state show` on the app: it prints the client secret.

### Rotating `terraform-oidc-spike-exchange`

Not exercised yet. Look the app up (the lookup is in the tnoff/terraform runbook linked above) with
`displayName eq "terraform-oidc-spike-exchange"` and deactivate it, then replace it from this stack:

```bash
bin/tf apply -replace=oci_identity_domains_app.oidc_exchange
```

Read the plan before accepting it: it should name only the app, its version helper and stamp, and the
Actions secrets and variables derived from them (the `OIDC_EXCHANGE_*` and `TF_VAR_oidc_exchange_*` values). Then, **from `trust/` in tnoff/terraform with this repo's `.envrc` loaded**,
`terragrunt apply`: the GitHub trust lists the app by `TF_VAR_oidc_exchange_client_id`, so it is stale until
then and every login fails in the meantime. Because every `terraform` job logs in through this app, run it
when no CI is in flight and re-run the whole pipeline afterwards. The trust ignores its rules (the provider
cannot read them back), so its plan shows only `oauth_clients`; do not apply a trust update you did not expect.

## Stored OCI credentials

What is left once everything that can federate has been moved. Every other IAM user is
federated and has no password, API key or token. Re-list the users with
`oci iam user list --all --query 'data[].name'` before trusting this table.

| Credential | Consumer | Rotate |
|---|---|---|
| `cluster-autoscaler-bot` API key | `cluster-autoscaler-oci-creds` Secret | Generation slot (`api_key_generations`). The upstream autoscaler has no resource-principal path, so this key stays |
| `oidc-jwks-publisher-bot` API key | `jwks-publisher-oci-creds` Secret | Generation slot. Kept on purpose: it must not depend on the federation it repairs |
| `os-push-dev-bot` customer secret key (`dev_discord_push`) | none in the cluster or CI; a local development key | Generation slot, or delete the user if it is unused |
| `terraform-admin` API key | `.envrc` on the operator's machine | [OCI keys generated by this stack](#oci-keys-generated-by-this-stack) |
| `mcp-readonly-bot` API key | `~/.oci/config` for the OCI MCP | [OCI keys generated by this stack](#oci-keys-generated-by-this-stack) |
| `terraform-oidc-spike-exchange` client secret | `OIDC_EXCHANGE_*` | [Token-exchange apps](#token-exchange-apps) |
| The human login | the operator, with MFA | Not rotated here |

## Credentials rotated elsewhere

- **Slot-managed (zero downtime):** the `cluster_autoscaler` and `oidc_jwks_publisher`
  API keys, the `dev_discord_push` customer secret key, and Discord webhooks
  rotate through generation flags in the `terraform` repo. Follow its
  [generation-slot rotation runbook](https://github.com/tnoff/terraform/blob/main/docs/generation-slot-rotation.md);
  never `apply -replace` them. (OCI auth tokens and the scanner and monitoring-reader
  keys no longer exist: tnoff/terraform#217, #252.)
- **Flux GitLab deploy token:** `terraform/infra/flux-deploy-token.tf` creates it
  and `bootstrap/` renders `flux-system-https` from it. Flux now syncs from
  GitHub with the `tnoff-flux` App, so this token is the rollback path. To
  rotate, set `var.flux_deploy_token_expires_at` (`infra/variables.tf`) to a
  new date, apply `infra/` (CI), then run the `bootstrap` workflow and approve its apply.
- **Grafana service-account tokens** are minted in-cluster by docker-apps'
  `grafana-sa-bootstrap` and are not terraform-managed.

## Cadence

Nothing enforces a schedule. The secret-age tracker reports each credential's
age from the timestamps and annotations described above. Target cadence,
decided 2026-11-28 (tnoff/terraform#341):

| Credential | Rotate every |
|---|---|
| GitHub App private keys (`tnoff-terraform`, `tnoff-ci`, changelog, `tnoff-flux`, `tnoff-backstage`, Renovate for this repo) | 12 months |
| `OIDC_EXCHANGE_CLIENT_SECRET` (token-exchange app client secret) | 12 months |
| Everything else operator-rotated | when the tracker flags it, or the vendor expires it |

Rotate sooner on suspected exposure, and whenever a repo that held a copy of a
key is made public or loses its ruleset. A key rotation touches every repo
that holds a copy (the tnoff-ci key is written by `terraform/infra`, so land a
change under `infra/` for it to re-apply), which is why the cadence is yearly
rather than tighter until those copies move to Vault.
