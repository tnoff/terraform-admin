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
| [Token-exchange apps](#token-exchange-apps) | `k8s-workload-exchange`, `terraform-oidc-spike-exchange` | Deactivate, then `apply -replace`, then re-render the consumer |
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
| `cloudflare_api_token` | Cloudflare dashboard, DNS provider token | `dns/` provider (CI only) |
| `cloudflare_dns01_token` | Cloudflare dashboard, separate zone-scoped token | `apps/` -> `cloudflare-api-key` Secret (cert-manager) |
| `openweather_api_key`, `bart_api_key` | OpenWeather; 511.org | `apps/` -> `mirror-*-key` Secrets in each mirror namespace |
| `five11_api_key` | 511.org (api.511.org token) | `apps/` -> `mirror-511-key` Secret in mirror-dublin and mirror-sanjose |
| `discord_spotify_client_id`, `discord_spotify_client_secret`, `discord_youtube_api_key` | Spotify dashboard; Google Cloud console | `apps/` -> `discord-search-creds` |
| `discord_vpn_private_key` | Self-generated WireGuard key (Mullvad holds only the public half) | `apps/` -> `discord-vpn-key` |
| `eastbay_contact_email`, `eastbay_contact_number`, `eastbay_email_host_user`, `eastbay_email_host_password`, `eastbay_flask_secret_key` | Business details; SMTP account; `python -c 'import secrets; print(secrets.token_hex(32))'` | `apps/` -> `eastbay-website-creds` |
| `grafana_admin_user`, `grafana_admin_password` | Chosen by the operator | `apps/` -> `grafana-admin-creds` (see caveat) |
| `backstage_mcp_token` | `openssl rand -hex 24` | `apps/` -> `backstage-mcp-token` |
| `hathor_vpn_private_key`, `hathor_vpn_addresses`, `hathor_vpn_server_hostnames` | A **new** Mullvad WireGuard device (mullvad.net/en/account/wireguard-config; never the discord device's): `PrivateKey` and `Address` from the same file, replaced together. The hostnames are a comma-separated list of Mullvad WireGuard servers that exist in gluetun's server list | `apps/` -> `hathor-vpn-key` |
| `hathor_url_token` | `openssl rand -hex 32`. The only auth on the hathor endpoint; rotate on any leak | `apps/` -> `hathor-url-token` |
| `hathor_google_api_key`, `hathor_twitch_client_id`, `hathor_twitch_client_secret` | Google Cloud console (YouTube Data API v3); dev.twitch.tv console | `apps/` -> `hathor-api-keys` |
| `hathor_youtube_cookies_b64` | A Netscape-format cookies file stripped to YouTube only (`scripts/filter_cookies.py cookies.txt --b64` in tnoff/docker-apps, which also prints the one-line base64; a raw browser export holds a login for every site). Expires; replace regularly | `apps/` -> `hathor-youtube-cookies` |
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

Two confidential Identity Domains apps hold the only long-lived secrets on the federated
paths. Each secret is useless on its own: an exchange also needs a token the matching
trust accepts (a GitHub OIDC token, or a ServiceAccount token the hosted key set verifies).

| App (display name) | Terraform | Trust that lists it | Where the secret goes |
|---|---|---|---|
| `k8s-workload-exchange` | `oci_identity_domains_app.k8s_exchange` (`k8s-oidc-trust.tf`) | `k8s-workloads` | `TF_VAR_k8s_exchange_client_*` Actions secrets, then `terraform` `apps/` writes `rpst-exchange-creds` in `monitoring`, `security-scanner`, `hathor`, `discord` and `backstage` |
| `terraform-oidc-spike-exchange` | `oci_identity_domains_app.oidc_exchange` (`oidc-trust.tf`) | `github-actions-oidc-spike` | `OIDC_EXCHANGE_*` Actions secrets on `terraform` |

These are **not slot-managed**. A rotation replaces the app, so it has a gap: from the moment
the old app stops working until the consumer is re-rendered, *new* exchanges fail with a 400
or 401. Tokens already issued keep working (the sidecar asks for 180 minutes and refreshes
every 90), so a gap of minutes goes unnoticed; do not leave one of hours.

An active app cannot be deleted: Terraform's delete returned `400-BadErrorResponse` with no
message. Deactivate it first (the retry then succeeded). Until the delete succeeds,
reactivating it is the rollback.

First exercised 2026-10-28 (the drill in tnoff/terraform#217). The sidecars that retried
during the gap logged 6 or 7 `401 invalid_client` failures and then issued a token, about
5 minutes 40 seconds after the deactivation: the `Apply` run took about a minute and the
kubelet needed another minute or two to refresh the mounted Secret.

**The alert margin is thin.** `rpst-exchange-failing` fires on a sidecar's 8th consecutive failed
exchange, which with the sidecar's backoff arrives roughly 3 to 4 minutes after its first failure
(observed: attempts 4 to 8 at 01:47:45, 01:47:54, 01:48:16, 01:49:06 and 01:50:48, the last one a
success). A sidecar is only affected if its 90-minute refresh falls inside the gap, so a gap of
about 6 minutes is often silent but can page. Keep the gap short (have the `apps/` change reviewed
and ready before step 3), and silence `rpst-exchange-failing` for the window if you want a quiet
run.

Never run `terraform state show` on these apps: it prints the client secret.

### Rotating `k8s-workload-exchange`

Look the ids up instead of copying them; nothing here is a fixed OCID. You need the CLI
profile of a user that manages the identity domain.

```bash
# The identity domain's URL (the stack's local.oidc_domain_endpoint; the domain is named "Default")
TENANCY=$(awk -F= '/^\[DEFAULT\]/{f=1;next} /^\[/{f=0} f&&/^tenancy/{gsub(/ /,"",$2);print $2;exit}' ~/.oci/config)
DOMAIN_URL=$(oci iam domain list --compartment-id "$TENANCY" --all \
  --query 'data[?"display-name"==`Default`].url | [0]' --raw-output)

# The app's id and whether it is active
oci identity-domains apps list --endpoint "$DOMAIN_URL" \
  --filter 'displayName eq "k8s-workload-exchange"' \
  --query 'data.resources[0].{id:id,active:active}'
```

1. **Preconditions.** A clean checkout of `main`, no `terraform` CI run in flight, and
   `kubectl` pointed at the cluster. Record the baseline (metadata only, never the Secret data):

   ```bash
   for ns in monitoring security-scanner hathor discord backstage; do
     kubectl -n $ns get secret rpst-exchange-creds \
       -o custom-columns='NS:.metadata.namespace,ROTATED:.metadata.annotations.secret-age-tracker\.tnoff/last-rotated'
   done
   ```

2. **Have the consumer change ready.** Open a one-line change under `terraform`'s `apps/` (a
   comment is enough) so you can merge it the moment step 4 finishes. Merged earlier, it
   re-renders the old credentials. See [How a rotation reaches
   consumers](#how-a-rotation-reaches-consumers).

3. **Deactivate the app** (cuts off new exchanges; this is where the gap starts):

   ```bash
   oci identity-domains app-status-changer put --endpoint "$DOMAIN_URL" \
     --app-status-changer-id "$APP_ID" \
     --schemas '["urn:ietf:params:scim:schemas:oracle:idcs:AppStatusChanger"]' \
     --active false
   ```

   with `APP_ID` taken from the lookup above. The response should show `"active": false`.

4. **Replace it, targeted:**

   ```bash
   bin/tf apply -replace=oci_identity_domains_app.k8s_exchange \
     -target=oci_identity_domains_identity_propagation_trust.k8s_workloads \
     -target='github_actions_secret.terraform["TF_VAR_k8s_exchange_client_id"]' \
     -target='github_actions_secret.terraform["TF_VAR_k8s_exchange_client_secret"]' \
     -target='github_actions_secret.terraform["TF_VAR_k8s_exchange_client_secret_rotated_at"]'
   ```

   The confirmation should read 3 to add, 3 to destroy and 4 to change: the app,
   `terraform_data.k8s_exchange_client_secret_version` and
   `time_static.k8s_exchange_client_secret_rotated_at` replaced; the `k8s-workloads` trust
   updated **in place** (only `oauth_clients`); and the three Actions secrets updated. The
   `-target` list is deliberate: an untargeted plan of this stack also showed about 60
   unrelated changes (SCIM `schemas` and `members` on the users and groups, and every
   `impersonation_service_users` rule on the `github_actions` trust as an addition, because
   the provider does not return them on read). Do not mix those into a rotation.

   Do not run a plain `plan` or `apply` between steps 3 and 4: it would recreate the
   `time_static` with today's date while the secret is still the old one.

5. **Re-render the consumer.** Merge the `apps/` change from step 2 and wait for
   `Apply` on `main` to finish (`gh run list --repo tnoff/terraform --workflow apply.yml`).

6. **Verify.**
   - The five annotations from step 1 now show today's date.
   - `kubectl -n monitoring get jobs | grep rpst-canary` shows a `Complete` run created after the merge.
   - A sidecar logged a fresh exchange: `kubectl -n <namespace> logs <pod> -c rpst --since=15m | grep "rpst issued"`, and
     no `RPST exchange failed` lines.
   - Quiet: `rpst-exchange-failing`, `rpst-canary-stale`, `oci-exporter-poll-*`.
   - `gh secret list --repo tnoff/terraform` shows the `TF_VAR_K8S_EXCHANGE_CLIENT_*` secrets updated.
   - Sidecars only exchange when their token is due (about every 90 minutes), so ones that were
     not mid-retry during the gap (Loki, Mimir, Tempo) prove nothing yet. Check their logs within
     90 minutes: `kubectl -n monitoring logs <pod> -c rpst --since=100m | grep -E "rpst issued|exchange failed"`.

7. **If it goes wrong.** Before the delete succeeds, reactivate the app (`--active true`) and
   the old secret works again. After the replace, the old secret is gone: re-run steps 3 to 5
   (another replace) rather than hunting for the old value. A sidecar that cannot exchange
   keeps its last token and retries forever; its liveness probe restarts it once the token is
   within a minute of expiry, which is roughly the time you have.

### Rotating `terraform-oidc-spike-exchange`

Same shape, not exercised yet. Look the app up with `displayName eq "terraform-oidc-spike-exchange"`,
deactivate it, then `bin/tf apply -replace=oci_identity_domains_app.oidc_exchange` with
`-target` on the app's dependents. Two differences from the in-cluster app:

- The trust it feeds is `github_actions`, whose plan shows every `impersonation_service_users`
  rule as an addition (see step 4 above). Read the plan before accepting it; do not apply a
  trust update you did not expect.
- The consumers are the `OIDC_EXCHANGE_*` Actions secrets, read by every `terraform` job,
  so run it when no CI is in flight and re-run the whole pipeline afterwards.

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
| `k8s-workload-exchange` and `terraform-oidc-spike-exchange` client secrets | `rpst-exchange-creds`; `OIDC_EXCHANGE_*` | [Token-exchange apps](#token-exchange-apps) |
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
  new date, apply `infra/` (CI), then apply `bootstrap/` as the operator.
- **Grafana service-account tokens** are minted in-cluster by docker-apps'
  `grafana-sa-bootstrap` and are not terraform-managed.

## Cadence

There is no enforced schedule. The secret-age tracker reports each
credential's age from the timestamps and annotations described above; rotate
before it flags one, and immediately on suspected exposure.
