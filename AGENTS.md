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

## Module sources

Modules come from `gitlab.com/tnoff-projects/terraform-modules` pinned to
specific commit SHAs. When bumping a module, bump both occurrences in
`main.tf` together if they reference the same source — Renovate currently
treats each `?ref=` independently.
