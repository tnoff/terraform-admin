# AGENTS.md

This file provides guidance to AI coding agents working in this repository. It
documents the non-obvious internals; the user-facing overview is in
[README.md](README.md), and setup/test/lint commands are in
[DEVELOPMENT.md](DEVELOPMENT.md).

## What this stack is

The bootstrap layer for the workload `terraform` repo. It owns the OCI IAM
user, KMS vault, state buckets, and the GitLab project + CI variables that
every other stack consumes. State is **local** by design — see "Bootstrap
pattern" in the README.

## Non-obvious internals

### `.envrc` generation

`local.envrc_lines` is built by `concat()` with explicit `"\n"` separators
rather than a heredoc. A heredoc preserves the source file's line endings; on
CRLF systems that broke `get_env()` substitution in the workload repo's
`root.hcl`. The current form forces LF regardless.

### `OCI_API_KEY_B64` vs `OCI_PRIVATE_KEY_PATH`

The PEM is base64-encoded into a single-line env var (`OCI_API_KEY_B64`) for
transit through CI variables. Multi-line env vars are flaky across shells. In
CI, `tnoff/terraform`'s `.github/actions/terragrunt` composite action (its
"Materialise the OCI API key" step) decodes it to disk and exports
`OCI_PRIVATE_KEY_PATH`; locally, `terraform-admin` writes the file directly
and `.envrc` points at it. Don't try to use multi-line PEMs as env vars —
that's the bug this works around.

The same value also still reaches `terraform`'s GitLab CI variables
(`module.terraform_gitlab`'s `pipeline_variables`), but that path is
rollback-only now — `.gitlab-ci.yml` no longer exists in the mirrored
content, since `terraform` went GitHub-canonical on 2026-09-04. See that
module's comment in `main.tf` before assuming anything runs on GitLab today.

### Duplicated `OCI_*` and `TF_VAR_oci_*`

`local.admin_secrets_bundle` and `local.terraform_ci_vars` both emit
`OCI_TENANCY_OCID` *and* `TF_VAR_oci_tenancy_ocid` (same value). This is
intentional: the OCI provider reads `OCI_*`, while `infra/`'s terraform code
reads them as input variables (`TF_VAR_*`) so it can echo them back into CI
variables on a later run.

### `moved {}` blocks at the bottom of `main.tf`

Five `moved` blocks lift orphan root-level resources into the
`terraform_state_buckets` module after a partial refactor. Keep them — they
preserve the cloud resources without recreate. If you delete them and re-apply
you will destroy and recreate the state buckets (and lose all state in them).

### Why `admin/` owns the GitLab project, and `terraform`'s GitHub Actions secrets

The GitLab project resource is here, not in the workload repo's `infra/`,
because admin already owns every secret that populates the CI variables.
Putting the project in `infra/` would mean a bootstrap-window hop where the
CI variables don't exist yet but jobs are scheduled. The comment above the
`gitlab_group` data source has the long version.

The same reasoning extends to `terraform`'s GitHub Actions secrets/variables
(`github_actions_secret.terraform` / `github_actions_variable.terraform`,
added when `terraform` went GitHub-canonical): admin owns what CI is allowed
to know, `infra/` owns the repository itself. That's an ordering
constraint, not just a layering one — `infra/` must have applied once
before these resources can find the repo to attach secrets to.

### Unmasked CI variables

`terraform_ci_vars_unmasked` is an explicit allowlist of variables that fail
GitLab's masking constraints (single-line, ≥8 chars, no `@`). Anything not in
that list is masked by default. If a new variable can't be masked (e.g.
contains `@` like an email), add it to the allowlist rather than turning
masking off globally.

### Two Discord bot tokens, not one

`discord_bot_token` and `discord_management_token` are two SEPARATE Discord
bot applications, not a naming quirk. `discord_bot_token` is the live
application bot's own identity (the one running in docker-apps, role
`vidya-game-machine`). `discord_management_token` is a bot that exists only
to let `terraform/discord`'s `discord` provider manage server structure
(roles/channels/webhooks); it has no docker-apps counterpart at all and
never reaches the cluster.

Before 2026-09-20 these were one variable (`discord_token`), reused for both
purposes -- wrong, not just imprecisely named: it meant the application
bot's own live credential was also sitting in `terraform`'s CI variables
with no reason to be there. If you're tempted to point `terraform/discord`'s
provider at `discord_bot_token` because it's populated and
`discord_management_token` isn't yet -- don't. Terraform's provider auth and
the live bot's identity are different blast radii on purpose.

**`discord_bot_token` IS pushed to `terraform`'s CI, and that's load-bearing
now, not an oversight.** It briefly wasn't, for the few hours between the
split above and the incident below -- the reasoning at the time was "nothing
in `terraform` reads it, so don't push it." That was true only because
`docker-apps` was still the one holding the live value, hand-sealed and
manually kept in sync. The first token rotation after the split (fresh
tokens minted for both bots, 2026-09-21) proved that manual-sync discipline
doesn't survive a real rotation under time pressure: `docker-apps`'
`discord-conf-secrets` went stale, and the bot crash-looped on `Improper
token has been passed.` for hours before anyone connected it to the
rotation. Fix: `apps/`'s `kubernetes_secret_v1.discord_bot_token` now creates
the `discord-bot-token` Secret directly from this variable (same pattern as
`discord-os-credentials`), and `docker-apps` no longer hand-seals
`DISCORD_TOKEN` at all. Don't re-remove `discord_bot_token` from
`terraform_ci_vars` without also removing that terraform-managed Secret and
putting the manual reseal step back -- doing one without the other silently
recreates this exact incident.

The same split shape got applied again immediately after, to
`cloudflare_api_token` / `cloudflare_dns01_token`: `cloudflare_api_token`
stays terraform-only (`terraform/dns`'s own provider), and
`cloudflare_dns01_token` is the one `apps/`'s
`kubernetes_secret_v1.cloudflare_api_key` consumes, replacing another
hand-sealed docker-apps SealedSecret. If a third credential shows up
needing this treatment, that's a pattern worth naming and writing up
properly rather than re-explaining per-variable a third time.

## Module sources

Modules come from `gitlab.com/tnoff-projects/terraform-modules` pinned to
specific commit SHAs. When bumping a module, bump both occurrences in
`main.tf` together if they reference the same source — Renovate currently
treats each `?ref=` independently.
