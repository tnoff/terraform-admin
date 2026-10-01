# Secret rotation runbook

How to rotate every credential the secret-age tracker surfaces, and
how to verify the rotation took. Companion to
[`projects/secret-age-tracker.md`](https://github.com/tnoff/docs/blob/main/projects/secret-age-tracker.md) (the tracker design) and
custom annotation keys (docker-apps TechDocs) (the annotation key registry).

> **As of 2026-06-25, all OCI auth_tokens / customer-secret-keys / the
> security-scanner API key / Discord webhooks are rotated via the
> zero-downtime generation-slot mechanism — see
> generation-slot rotation runbook (terraform TechDocs), NOT the `apply -replace=`
> commands below (which are kept only for the non-slot creds: terraform-admin
> api_keys, GitLab PATs/trigger/runner tokens, SealedSecrets).**

> **As of 2026-09-21, "SealedSecrets" above is history, not a live
> category.** [`projects/sealed-secrets-terraform-admin-migration.md`](https://github.com/tnoff/docs/blob/main/projects/sealed-secrets-terraform-admin-migration.md)
> migrated the last one (`grafana-admin`) and decommissioned the
> controller entirely — Layers 7 and 8 below, the SealedSecrets rows in
> "Where things live" and "Recommended cadences", and the TL;DR bullet
> about re-sealing are all retired. Left in place rather than deleted:
> if you're reading an old commit or PR that references this procedure,
> it was real at the time.

> Each credential this stack holds or originates is catalogued as a
> Resource in this repo's `catalog-info.yaml` (metadata only, never values);
> start there to see what exists and what consumes it.

## TL;DR

- Most rotations are `terraform apply -replace=<resource>` against
  one of three stacks. Always run from a clean checkout, never on
  a feature branch.
- After rotation, the timestamp it produces flows automatically
  through CI variables → the `layer-1-rotation-ledger` ConfigMap →
  the tracker's next weekly report. No operator post-step needed
  for tracking.
- ~~For SealedSecrets in `docker-apps`, rotation also requires a
  re-seal + commit~~ — **retired 2026-09-21**, no SealedSecrets left.
  Historical: bump the `secret-age-tracker.tnoff/last-rotated`
  annotation in the plaintext manifest to today's date *before*
  re-sealing, so the new date travels inside the encrypted blob. That
  annotation, not `git log`/GitLab blame, is the authoritative signal
  (see [`projects/secret-age-tracker-github-reader.md`](https://github.com/tnoff/docs/blob/main/projects/secret-age-tracker-github-reader.md) — the old GitLab-blame
  reader is retired).
- For the OCI IAM creds (api_keys, auth_tokens, customer_secret_keys),
  rotation is fully captured by the next OCI API call — the reader
  picks up the new `time_created` directly.

## Where things live

| Source of truth | Repo / file | Tracking signal |
|---|---|---|
| Admin tfvars | `terraform-admin/variables.tf` + operator's local `.envrc` | `terraform_data` + `time_static` in `terraform-admin/rotation-tracking.tf` |
| OCI api_keys | `terraform-admin/main.tf` (terraform_admin, mcp_readonly) + `terraform/oci/oci.tf` (security_scanner_api_key) | OCI IAM `time_created` |
| OCI auth_tokens / customer_secret_keys | `terraform/oci/oci.tf` (per push-bot via `oci/iam-user` module) | OCI IAM `time_created` |
| Discord webhooks | `terraform/discord/main.tf` | `terraform_data` + `time_static` in same file |
| GitLab pipeline trigger + runner tokens | `terraform/infra/` | `terraform_data` + `time_static` in `infra/repos.tf` and `infra/gitlab.tf` |
| Terraform-managed k8s Secrets | `terraform/apps/main.tf` | `secret-age-tracker.tnoff/last-rotated` annotation (seeded `"unknown"`) |
| ~~SealedSecrets~~ | **Retired 2026-09-21** — the last one (`grafana-admin`) migrated to terraform and the controller was decommissioned; see [`projects/sealed-secrets-terraform-admin-migration.md`](https://github.com/tnoff/docs/blob/main/projects/sealed-secrets-terraform-admin-migration.md) and Layer 7 below | n/a |
| Flux deploy token | `flux-system-https` Secret in `flux-system` ns, sourced from `gitlab_project_deploy_token.flux` in `terraform/infra/flux-deploy-token.tf`. Wired up in `terraform/bootstrap/main.tf` (Stage 3a of the cluster-bootstrap-stack reorg moved it out of `apps/`). | Rotation: `time_static` auto-capture in infra/ → `secret-age-tracker.tnoff/last-rotated` annotation. Expiry: `secret-age-tracker.tnoff/expires-at` annotation (sourced from infra output `flux_deploy_token_expires_at`) → tracker's k8s reader emits a days-to-expiry warning inside the warn window |
| Flux→Grafana SA token | `flux-grafana-token` Secret in `flux-system` ns, minted **in-cluster** by the `grafana-sa-bootstrap` Job (`docker-apps/monitoring/grafana-sa-bootstrap`) — **no longer terraform-managed**. Used by Flux notification-controller to POST deploy-marker annotations to Grafana. | `creationTimestamp` (k8s reader); the Job re-mints only when the token stops authenticating, so no annotation hatch |

## Rotation procedures

### Layer 1: admin tfvars (8)

> **Stale list.** The eight names below date from this runbook's
> original writing. `variables.tf` and `rotation-tracking.tf` are the
> current source of truth: for example `discord_token`, `github_token`
> and `bot_github_token` no longer exist, and the Discord bot, Cloudflare
> DNS-01, eastbay, Grafana, openweather/bart, and GitHub App credentials
> are tfvars here now. The procedure itself still applies.

For each of: `discord_token`, `cloudflare_api_token`, `github_token`,
`bot_github_token`, `gitlab_api_key`, `gitlab_bot_api_key`,
`ssh_public_key`, `secret_age_tracker_gitlab_token`.

> `mcp_gitlab_token` was a 9th entry until 2026-07-14. The in-cluster
> `mcp-gitlab` pod was retired (docker-apps `ecec641`) and the local
> gitlab MCP now uses its own hand-minted `read_api` PAT in
> `~/.mcp-local/gitlab/.env`, so the tfvar + its Secret/ledger/rotation
> plumbing were removed (`terraform!188` + `terraform-admin!24`). Rotate
> that PAT locally — see local MCP containers (mcp-local TechDocs).

**Procedure:**

1. Generate the new value in its vendor system (GitLab settings,
   Cloudflare dashboard, Discord developer portal, GitHub
   settings, `ssh-keygen` for the SSH public key).
2. Update the value in `terraform-admin/`'s `.envrc` (or the
   matching env var) — `direnv allow` to re-export.
3. `terraform apply` in `terraform-admin/` from a clean checkout.
4. Confirm the matching `time_static.<name>_rotated_at` was
   replaced (look for it in the `apply` diff or
   `terraform output time_static.<name>_rotated_at.rfc3339`).
5. Confirm the new value was pushed to the `terraform` GitLab
   project's CI variables:
   ```
   glab variable get TF_VAR_<name> --repo tnoff-projects/terraform
   glab variable get TF_VAR_<name>_rotated_at --repo tnoff-projects/terraform
   ```
6. Trigger a no-op pipeline on `terraform/` main (or wait for the
   next merge) so the apps/ stack writes the new timestamp into
   the `layer-1-rotation-ledger` ConfigMap.
7. The tracker's next weekly run reads the ConfigMap; nothing
   else to do.

**Special downstream cases:**

- `discord_token` and `cloudflare_api_token` have **separate**,
  similarly-named SealedSecrets in `docker-apps` that are **not**
  copies of these tfvars — they are distinct credentials for the same
  vendor (see [`findings/2026-06-16-sealed-secrets-vs-terraform-audit.md`](https://github.com/tnoff/docs/blob/main/findings/2026-06-16-sealed-secrets-vs-terraform-audit.md)):
  - terraform's `discord_token` is the **Terraform bot** token (drives
    the `Lucky3028/discord` provider); the discord-bot app's runtime
    `DISCORD_TOKEN` in `apps/discord/secrets-conf.yaml` is a different
    bot identity.
  - terraform's `cloudflare_api_token` is the **full-permission**
    provider token; `infrastructure/configs/cert-manager/cloudflare-api-key.yaml`
    holds a **zone-scoped DNS-01 solver** token for cert-manager.

  So rotating these tfvars in terraform-admin does **not** require
  re-sealing anything — the SealedSecrets rotate independently on their
  own vendor cadence (Layer 7).
- `ssh_public_key` bakes into the OKE node pool cloud-init.
  Cycling pool nodes (rolling, via terraform `-replace=` on the
  node-pool resource) propagates the new authorized key; existing
  long-lived nodes keep the old key until cycled.

### Layer 2: terraform-generated OCI api_keys (3)

| User | Stack | Command |
|---|---|---|
| `terraform-admin` | terraform-admin | `terraform apply -replace=tls_private_key.terraform_admin` |
| `mcp-readonly-bot` | terraform-admin | `terraform apply -replace=tls_private_key.mcp_readonly` |
| `security-scanner-read-bot` | terraform/oci | **slot-managed — `api_key_generations` in `oci/terragrunt.hcl`; see generation-slot rotation runbook (terraform TechDocs)** (not `-replace=`) |

**Effect**: a new RSA keypair is generated. The public half re-registers
in OCI as a fresh `oci_identity_api_key` (new fingerprint, new
`time_created`). The private half is written to disk
(`generated-output/<name>.pem`) and pushed as the corresponding
`OCI_API_KEY_B64` / similar CI variable. The next CI run on the
workload picks up the new key automatically.

**Verify:**

```bash
# OCI side: confirm a fresh api_key time_created
oci iam api-key list --user-id <user-ocid>

# CI side: confirm the new fingerprint propagated
glab variable get OCI_FINGERPRINT --repo tnoff-projects/terraform
```

The tracker's OCI IAM reader picks up the new `time_created` on the
next weekly run; no annotation or ledger to update.

### Layer 3: OCI auth_tokens / customer_secret_keys (per push-bot)

> ⚠️ **Superseded — do NOT `apply -replace=`.** As of 2026-06-25 every OCI
> auth_token and customer-secret-key is **generation-slot managed** (the
> resources moved to `oci_identity_auth_token.bots["name:gen"]` /
> `oci_identity_customer_secret_key.csk["name:gen"]`, so the old
> `module.X.oci_identity_*.this` addresses no longer exist, and
> `-replace=` would reintroduce the destroy-then-recreate auth gap this
> mechanism removed). Rotate these via the flag bump in
> **generation-slot rotation runbook (terraform TechDocs)** (`auth_token_generations` /
> `customer_secret_key_generations` in `terraform/oci/terragrunt.hcl`).

### Layer 4: Discord webhooks (5)

> ⚠️ **Superseded — do NOT `apply -replace=`.** As of 2026-06-25 the
> Discord webhooks are **generation-slot managed**
> (`discord_webhook.webhooks["name:gen"]`), keyed by `webhook_generations`
> in `terraform/discord/terragrunt.hcl`. There are **5** (infra/grafana,
> build_failure, security, image_deletions, secret_age) — consumed by
> `apps/` Secrets (scanner/secret-age CronJobs, grafana Deployment) and
> `infra/` GitLab CI group vars. The `mr_opened` / `mr_merged` pair was
> retired 2026-08-15 with the `#mr-opened` / `#mr-merged` channels — see
> [[`findings/2026-08-15-mr-notify-retirement.md`](https://github.com/tnoff/docs/blob/main/findings/2026-08-15-mr-notify-retirement.md)](https://github.com/tnoff/docs/blob/main/findings/2026-08-15-mr-notify-retirement.md).
> Rotate via the
> flag bump in **generation-slot rotation runbook (terraform TechDocs)** (grafana needs a
> roll — it has a Reloader annotation on `grafana-alerts`).

### Layer 5: GitLab pipeline trigger (orphaned) — runner tokens all gone

| Resource | Drives | Rotation |
|---|---|---|
| `gitlab_pipeline_trigger.docker_apps_bump_pin_trigger` | `DOCKER_APPS_TRIGGER_TOKEN` on 7 workload repos | `terragrunt -chdir=terraform/infra apply -replace=gitlab_pipeline_trigger.docker_apps_bump_pin_trigger` |

**Effect**:
- **Pipeline trigger**: ~~terraform re-pushes the new token to all 7 consuming
  workload repos as `DOCKER_APPS_TRIGGER_TOKEN` on the same apply.~~
  **Orphaned 2026-09-04 — nothing consumes this token.** `docker-apps` is
  GitHub-canonical and its bump arrives as a `repository_dispatch`
  authenticated by the `tnoff-ci` App, so the 7 producers no longer pass
  `DOCKER_APPS_TRIGGER_TOKEN` or `DOCKER_APPS_PROJECT_ID` at all. Rotating it
  is harmless and pointless; the resource and its Actions secrets are phase-8
  teardown. **Nothing here replaces it** — the App key's rotation is tracked
  separately, in terraform-admin's `rotation-tracking.tf`.
- **Runner tokens**: ~~terraform rewrites the `gitlab-runner-token` k8s Secret…~~
  **Gone 2026-09-05.** Both self-hosted runners are retired — `oke_elevated` with
  the `terraform-apps` identity it ran as, `oke_default` with the last GitLab
  schedule that fed it — along with their registrations, their k8s Secrets and the
  `ci` node pool their jobs ran on. There is no runner token to rotate. Break-glass
  GitLab CI falls back to GitLab's *shared* runners, which need no token here.

  *`oke_elevated` was the third entry here until 2026-09-04.* That runner served only
  terraform's `apps`/`dns` jobs, which now run on GitHub-hosted runners through an OCI
  Bastion tunnel; the registration, its `gitlab-runner-elevated-token` Secret and the
  `terraform-apps` identity it ran as were all deleted. Nothing to rotate.

### Layer 6: Terraform-managed k8s Secrets (15, downstream)

These wrap upstream values (OCI auth_tokens, Layer-1 tfvars, Grafana
SA token, etc.). Rotation is **always** done upstream — never directly
on the k8s Secret. The annotation
`secret-age-tracker.tnoff/last-rotated` updates automatically when
the operator manually annotates it post-rotation, or when terraform's
apply path bumps it via a future enhancement.

For now, the OCI reader is the canonical source for OCI-backed
Secrets, and the layer-1 ledger is canonical for tfvar-derived ones.
The k8s reader serves as a coarse cross-check.

**Special k8s Secret rotations not covered by upstreams:**

- **Grafana SA tokens** — `mcp-grafana` (Viewer role, `monitoring` ns) and
  `flux-grafana-token` (Editor role, `flux-system` ns — Flux
  notification-controller posts deploy-marker annotations) are **no longer
  terraform-managed**. Both are minted **in-cluster** by the one
  `grafana-sa-bootstrap` Job (`docker-apps/monitoring/grafana-sa-bootstrap`,
  `reconcile_sa` list), which re-mints a token only when the stored one stops
  authenticating (so they survive a Grafana DB rebuild without a terraform
  apply) and **deletes all stale SA tokens before minting** (old token revoked
  automatically). To force a rotation, invalidate the current token, re-run the
  shared Job, then handle the consumer:

  ```bash
  # --- mcp-grafana (Viewer): consumed by the LOCAL grafana MCP. The in-cluster
  #     pod was retired 2026-07-09, so nothing in-cluster reads this Secret —
  #     deleting it is safe.
  kubectl -n monitoring delete secret mcp-grafana

  # re-run the shared bootstrap Job (Flux-managed: delete + reconcile)
  kubectl -n monitoring delete job grafana-sa-bootstrap
  flux reconcile kustomization <name> --with-source   # find via: flux get kustomizations
  kubectl -n monitoring wait --for=condition=complete job/grafana-sa-bootstrap --timeout=180s

  # copy the fresh token into the local MCP env (local MCP containers, mcp-local TechDocs)
  NEW=$(kubectl -n monitoring get secret mcp-grafana \
          -o jsonpath='{.data.service-account-token}' | base64 -d)
  sed -i "s|^GRAFANA_SERVICE_ACCOUNT_TOKEN=.*|GRAFANA_SERVICE_ACCOUNT_TOKEN=${NEW}|" \
    ~/.mcp-local/grafana/.env

  # --- flux-grafana-token (Editor): consumed IN-CLUSTER by the Flux
  #     notification-controller, which DOES need a restart (secretKeyRef doesn't
  #     refresh on update).
  kubectl -n flux-system delete secret flux-grafana-token
  kubectl -n monitoring delete job grafana-sa-bootstrap
  flux reconcile kustomization <name> --with-source
  kubectl -n flux-system rollout restart deploy/notification-controller
  ```

  No `terraform apply -replace=` and no manual annotation bump — `reconcile_sa`
  stamps a fresh `secret-age-tracker.tnoff/last-rotated` on the re-minted Secret.

### Cluster bootstrap: Flux

Flux's `flux-system` GitRepository pulls `docker-apps` for cluster
reconciliation. The credential it uses lives as a Secret in the
`flux-system` namespace; the GitRepository's `pullSecret` is set on the
**FluxInstance** in `terraform/bootstrap/flux.tf` — Flux is now installed
via the Flux Operator, so the committed `gotk-sync.yaml` was removed. It
points at the `flux-system-https` Secret.

After the SSH→HTTPS migration (terraform!64 + docker-apps!216), this
Secret is terraform-managed:
- **Resource**: `kubernetes_secret_v1.flux_system_https` in
  `terraform/bootstrap/main.tf` (Stage 3a of the cluster-bootstrap-stack
  reorg moved it here from `apps/`; `bootstrap` is operator-run via the
  bastion, not CI), named `flux-system-https`.
- **Source**: `gitlab_project_deploy_token.flux` in `terraform/infra/flux-deploy-token.tf`,
  scoped to `read_repository` only, with `expires_at` operator-managed
  via `var.flux_deploy_token_expires_at` (default `2027-06-11`).
- **Auto-capture**: `time_static.flux_deploy_token_rotated_at`
  stamps the rotation moment; the apps/ stack writes that RFC3339
  string directly into the Secret's annotation, so the tracker sees
  the canonical rotation date.

**Rotation procedure (post-migration, expected steady state):**

1. Decide a new expiry — typically `(today + 1y).strftime('%Y-%m-%d')`.
2. Update `var.flux_deploy_token_expires_at` in `terraform/infra/variables.tf`
   (or set via `TF_VAR_flux_deploy_token_expires_at` in CI).
3. `terragrunt apply` on `infra/`. The `gitlab_project_deploy_token` provider
   treats `expires_at` as force-new, so terraform replaces the token,
   the auto-capture pair refreshes, and `flux_deploy_token_password`
   output rotates.
4. `terragrunt apply` on `bootstrap` (operator-run via the bastion —
   this stack is **not** in CI). The new password flows into the
   `flux-system-https` Secret. Flux's GitRepository controller picks
   it up on its next reconcile (~1m).
5. Verify with `flux get sources git flux-system` — Ready: True with
   a recent `LastUpdateTime`.

The `infra/` token rotation (step 3) happens automatically when CI runs
the DAG on merge to `terraform/` main; the `bootstrap` Secret re-render
(step 4) is the one operator step, since `bootstrap` is applied locally
via the bastion, not by a pipeline.

**SSH→HTTPS cutover sequence (one-time migration):**

This is the runbook for the initial migration from the bootstrap
SSH key to the terraform-managed deploy token. Each step is
verifiable before moving on.

1. **Land the RBAC update** ([docker-apps!216](https://gitlab.com/tnoff-projects/docker-apps/-/merge_requests/216)'s
   first commit only, or merge the full MR but don't worry — the
   gotk-sync flip won't bite until the Secret exists).
   ```bash
   # Verify the binding is in place
   kubectl auth can-i create secrets -n flux-system \
     --as=system:serviceaccount:gitlab-runner:terraform-apps
   ```
   *(Historical: this migration completed in 2026-06. The `terraform-apps` SA was
   deleted on 2026-09-04, so this check now returns `no` for a subject that does not
   exist. CI is cluster-admin via the OCI user and needs no binding.)*

2. **Land terraform changes** ([terraform!64](https://gitlab.com/tnoff-projects/terraform/-/merge_requests/64)).
   CI applies `infra/` (creates the deploy token), then `apps/` (writes
   the `flux-system-https` Secret).
   ```bash
   # Confirm both deploy keys exist on the GitLab project
   glab repo deploy-key list --repo tnoff-projects/docker-apps
   # Output should include the bootstrap SSH key + the new "flux-system" token

   # Confirm the new k8s Secret materialized
   kubectl -n flux-system get secret flux-system-https \
     -o jsonpath='{.data.username}' | base64 -d
   # Output: "flux"
   ```

3. **Land the gotk-sync flip** (docker-apps!216's second commit). Flux
   picks up the new GitRepository spec on its next reconcile.
   ```bash
   # Verify the new auth path works
   flux get sources git flux-system
   # Expect: Ready: True, recent LastUpdateTime

   # Confirm GitRepository sees no errors
   kubectl -n flux-system describe gitrepository flux-system | tail -20
   ```

4. **Confirm steady-state reconciliation**.
   Apply any minor change to docker-apps (e.g. a comment edit, MR
   merge), confirm Flux pulls it within 1 minute.

5. **Clean up the old SSH path**.
   ```bash
   # Old SSH Secret no longer referenced; delete it
   kubectl -n flux-system delete secret flux-system

   # Find the old SSH deploy key's id and delete from GitLab
   glab repo deploy-key list --repo tnoff-projects/docker-apps
   glab repo deploy-key delete <ssh-key-id> --repo tnoff-projects/docker-apps
   ```

If you need to roll back partway through (Flux fails to reconcile
on HTTPS), revert docker-apps!216's second commit only — the
`flux-system` SSH Secret + the SSH deploy key on GitLab are still
in place at that point.

**Pre-migration legacy procedure** (kept for reference; the
post-migration procedure above supersedes this):

**Procedure (manual rotation, preferred over `flux bootstrap --force`):**

1. Generate a new SSH keypair locally:
   ```bash
   ssh-keygen -t ed25519 -f /tmp/flux-key -N "" -C "flux-system rotation $(date +%Y-%m-%d)"
   ```
2. Add the new public key as a deploy key on the
   `tnoff-projects/docker-apps` GitLab project with **write access**
   (Flux needs write to push the README badge on reconcile errors).
   Note its `id` for step 6.
3. Verify with `glab repo deploy-key list --repo tnoff-projects/docker-apps`.
4. Replace the in-cluster Secret with the new keypair:
   ```bash
   kubectl -n flux-system delete secret flux-system
   flux create secret git flux-system \
     --url=ssh://git@gitlab.com/tnoff-projects/docker-apps \
     --private-key-file=/tmp/flux-key
   ```
   Use `delete` + `create` rather than `kubectl patch` — patching in
   place does **not** bump `creationTimestamp`, and the tracker
   would keep reporting the old date.
5. Annotate the new Secret for sharper tracking (so it shows up via
   the annotation hatch rather than the creationTimestamp
   fallback):
   ```bash
   kubectl -n flux-system annotate secret flux-system \
     secret-age-tracker.tnoff/last-rotated=$(date +%Y-%m-%d)
   ```
6. Remove the old deploy key from GitLab:
   ```bash
   glab repo deploy-key delete <old-id> --repo tnoff-projects/docker-apps
   ```
7. Force Flux to reconcile with the new key:
   ```bash
   flux reconcile source git flux-system
   ```
8. Wipe the local key material:
   ```bash
   shred -u /tmp/flux-key /tmp/flux-key.pub
   ```

**Verify:**

```bash
# Reconciliation should be Ready: True with a recent LastUpdateTime
flux get sources git flux-system

# No error events on the GitRepository
kubectl -n flux-system describe gitrepository flux-system | tail -20
```

If you see `Permission denied (publickey)`, the GitLab deploy key
wasn't registered or wasn't given write access — re-check step 2.

**Caveats:**

- `kubectl edit secret flux-system` to patch the key material in
  place does **not** bump `creationTimestamp`. Always delete +
  recreate.
- The GitLab deploy key on the project side has its own lifetime
  and the tracker's GitLab reader does not currently enumerate
  project deploy keys. Rotate both halves together; the in-cluster
  Secret is the rotation signal the tracker watches.
- A future enhancement would add `gl.projects.deploykeys.list()`
  to `readers/gitlab.py` so the deploy-key side is independently
  visible. Not blocking — the in-cluster Secret tracking catches
  the rotation correctly when the procedure above is followed.

### Layer 7: SealedSecrets in docker-apps — RETIRED 2026-09-21

No SealedSecrets exist in the fleet any more; the procedure below is
historical. See [`projects/sealed-secrets-terraform-admin-migration.md`](https://github.com/tnoff/docs/blob/main/projects/sealed-secrets-terraform-admin-migration.md)
and [`findings/2026-09-21-sealed-secrets-controller-decommissioned.md`](https://github.com/tnoff/docs/blob/main/findings/2026-09-21-sealed-secrets-controller-decommissioned.md).

For each of the 8: `grafana-admin`, `discord-conf-secrets`,
`cloudflare-api-key`, `vpn-secrets`, eastbay `website-secrets`,
`mirror-castro`/`mirror-concord`/`mirror-sanjose` `mirror-api-keys`.

**A 9th, gitlab-runner `dockerhub-auth`, is gone** — retired with the
self-hosted OKE runners (phase 8, 2026-09-04/05). Confirmed absent from
`docker-apps` as of 2026-09-18; drop it from any list still carrying it.

**`mirror-sanjose` is the third mirror namespace, added 2026-08-12, and was
missing from this list until 2026-08-27.** It seals only
`OPENWEATHER_API_KEY` — castro and concord also carry `BART_API_KEY` — so an
OpenWeather rotation that follows the old list rotates two of three
namespaces and leaves sanjose serving the revoked key. Count the namespaces
in `apps/mirror/` rather than trusting a list; a fourth location is a
routine addition.
(Postgres credentials are now operator-issued, **not** SealedSecrets — see
database backup (database-backup TechDocs).)

**Procedure:**

1. Generate the new secret value (Discord token rotation, Spotify
   API rotation, Postgres user password change in `psql`, etc.).
2. In the plaintext SealedSecret YAML, bump
   `spec.template.metadata.annotations["secret-age-tracker.tnoff/last-rotated"]`
   to today's date (`YYYY-MM-DD`) — this is what makes the rotation
   visible to the tracker, since the value only exists inside the
   encrypted blob otherwise.
3. Locally re-seal the affected key into the same SealedSecret YAML —
   the annotation bump from step 2 must already be in the file before
   this runs, so it travels through the re-encrypt:
   ```bash
   echo -n "<new value>" | kubectl create secret generic <name> \
     --dry-run=client --from-file=<key>=/dev/stdin -o yaml | \
     kubeseal --controller-namespace sealed-secrets -o yaml \
     --merge-into <path/to/file.yaml>
   ```
   (Exact incantation depends on your local `kubeseal` setup; see
   workload deployment (docker-apps TechDocs) for Flux/sealed-secrets
   context.)
4. Commit the updated YAML to `docker-apps`, PR + merge.
5. Flux reconciles; the matching `Secret` is rewritten in-cluster,
   annotation and all.
6. The consumer pod may need a rollout restart if it caches the
   secret at startup (Discord bot, Postgres clients, etc.).

The tracker's k8s reader picks up the annotation directly on its next
run — no separate signal to wire up. (The old GitLab-blame reader that
used to infer this from commit history is retired; see
[`projects/secret-age-tracker-github-reader.md`](https://github.com/tnoff/docs/blob/main/projects/secret-age-tracker-github-reader.md).)

### Layer 8: Sealed-secrets controller key — RETIRED 2026-09-21

No controller, no key, nothing to roll before the `2026-12-12` cert
expiry this section describes — see
[`findings/2026-09-21-sealed-secrets-controller-decommissioned.md`](https://github.com/tnoff/docs/blob/main/findings/2026-09-21-sealed-secrets-controller-decommissioned.md). The
procedure below is historical.

Distinct from Layer 7 (which rotates the *values* inside SealedSecrets): this
is the controller's own **encryption key** that seals/unseals them. As of
2026-07-14 the 7 accumulated keys were consolidated to **one**
(`sealed-secrets-keyptkzt`) and renewal is **frozen** (`keyrenewperiod: "0"` on
the sealed-secrets HelmRelease), so nothing auto-replaces it — rotation is a
**deliberate, scheduled** task. The key's cert expires `2026-12-12`; roll it
before then.

**Where it lives:** the single key (`tls.crt`/`tls.key`) is held in
`terraform-admin` **local** state as two sensitive base64 tfvars
(`sealed_secrets_tls_crt_b64` / `sealed_secrets_tls_key_b64`), surfaced to the
`bootstrap` stack via the operator's `.envrc` only (never CI vars).
`terraform/bootstrap` seeds it as a `kubernetes_secret_v1`
(`type: kubernetes.io/tls`, label
`sealedsecrets.bitnami.com/sealed-secrets-key: active`) in the `sealed-secrets`
namespace, adopted via `import`. See [`projects/sealed-secrets-key-bootstrap.md`](https://github.com/tnoff/docs/blob/main/projects/sealed-secrets-key-bootstrap.md).

**Rotation procedure (deliberate; do before the `2026-12-12` cert expiry):**

**This does not touch `secret-age-tracker.tnoff/last-rotated`** — the
values inside are unchanged, only the ciphertext's encrypting key, so
there's nothing to bump (unlike Layer 7's procedure, which does).

1. Mint a fresh key so the controller has a new "latest" to seal against.
2. Re-encrypt **all 8** SealedSecrets against it:
   ```bash
   for f in <the 8 SealedSecret files>; do
     kubeseal --controller-namespace sealed-secrets --re-encrypt \
       < "$f" > "$f.new"
     [ -s "$f.new" ] && grep -q 'kind: SealedSecret' "$f.new" && mv "$f.new" "$f"
   done
   ```
   > ⚠️ **FOOTGUN:** `kubeseal --re-encrypt` (v0.23.0) reads the SealedSecret
   > from **STDIN** and **silently ignores `-f`** — empty stdin yields empty
   > output + exit 0 and **blanks the file**. Always feed it `< "$f"` and guard
   > with `[ -s ]` + a `kind: SealedSecret` check before any `mv`. Also strip the
   > trailing blank line `-o yaml` appends (yamllint `empty-lines`). Commit, let
   > Flux apply, confirm every SealedSecret is `Synced=True`.
3. Delete the old key (`kubectl -n sealed-secrets delete secret <old-key>`),
   restart the controller, and confirm all 8 re-reconcile to `Synced=True` with
   only the new key present.
4. Update the `terraform-admin` backup tfvars to the new key and re-apply
   `bootstrap` (operator-run via bastion) so green-field seeds the new key.

The 9 SealedSecrets: `cloudflare-api-key`, `discord-conf-secrets`,
`vpn-secrets`, eastbay `website-secrets`, gitlab-runner `dockerhub-auth`,
`mirror-castro`/`mirror-concord`/`mirror-sanjose` `mirror-api-keys`,
`grafana-admin`.

## What you do NOT rotate

- **KMS keys** (`module.vault.kms_key`) — by design. Re-keying
  invalidates every state bucket and would require a full re-encrypt.
- **OCI compartment OCIDs / tenancy OCID / object-storage namespace
  IDs** — not secrets; identifiers.
- **Operator's main `~/.oci/config` DEFAULT profile** — Layer 0,
  outside the tracker's scope. Rotate annually via console + update
  `~/.oci/config` by hand.
- **Operator's vendor passwords / 2FA seeds** — Layer 0.

## Recommended cadences

| Class | Suggested cadence |
|---|---|
| GitLab/GitHub PATs (Layer 1) | Match PAT `expires_at` — the tracker's GitLab reader surfaces upcoming expiries inside the warn window |
| OCI api_keys (Layer 2) | Annual minimum; quarterly if you want to exercise the rotation muscle |
| OCI auth_tokens / customer_secret_keys (Layer 3) | Same as Layer 2 |
| Discord webhooks (Layer 4) | Only when a leak is suspected; webhook URLs aren't access-controlled by anything else |
| GitLab pipeline trigger + runner tokens (Layer 5) | Annual |
| ~~SealedSecrets (Layer 7)~~ | **Retired 2026-09-21** — no SealedSecrets left in the fleet; see Layer 7 below |
| ~~Sealed-secrets controller key (Layer 8)~~ | **Retired 2026-09-21** — controller decommissioned, no key to roll; see Layer 8 below |
| Flux deploy token | GitLab enforces expiry — set `var.flux_deploy_token_expires_at` to 1 year out and bump as it approaches. The tracker surfaces upcoming expiry inside the warn window via the `secret-age-tracker.tnoff/expires-at` annotation on the `flux-system-https` Secret (no GitLab API call needed). |
| OKE worker-node SSH public key | Annual at minimum; sooner if a node-pool worker is suspected compromised |

The tracker's default thresholds (90d warn / 180d rotate-now) match
"annual rotation gives you 180 days of headroom" — anything sitting
red for a week or two suggests it's time.

## Cross-references

- Design: [`projects/secret-age-tracker.md`](https://github.com/tnoff/docs/blob/main/projects/secret-age-tracker.md)
- Annotation registry: custom annotation keys (docker-apps TechDocs)
- terraform-admin runner-options analysis: [`findings/2026-06-10-terraform-admin-runner-options.md`](https://github.com/tnoff/docs/blob/main/findings/2026-06-10-terraform-admin-runner-options.md)
- Local MCP containers (gitlab PAT + grafana token consumer side): local MCP containers (mcp-local TechDocs)
- Bootstrap doc (for the terraform-admin → terraform CI variable channel): [infra-bootstrap.md](infra-bootstrap.md)

---

## Verified against

| Project | SHA | Date |
|---|---|---|
| `terraform` | `b258368` | 2026-09-21 |
| `terraform-admin` | `7fcfabf` | 2026-09-21 |
| `docker-apps` | `fb82215` | 2026-09-21 |
| `oke-security-scanner` | `9da4e92` | 2026-06-13 |
