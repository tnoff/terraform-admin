# AGENTS.md

Guidance for AI coding agents working in this repository. It documents the
non-obvious internals; the user-facing overview is in [README.md](README.md),
setup/test/lint commands are in [DEVELOPMENT.md](DEVELOPMENT.md), and how the
handoff to the workload repo works is in
[docs/infra-bootstrap.md](https://github.com/tnoff/terraform-admin/blob/main/docs/infra-bootstrap.md).

## What this stack is

The bootstrap layer for the workload `terraform` repo. It owns the OCI IAM
user, KMS vault and state buckets, plus the credentials and repo settings the
workload repo's CI consumes. State is **local** by design.

## Non-obvious internals

### `.envrc` generation

`local.envrc_lines` is built by `concat()` with explicit `"\n"` separators
rather than a heredoc. A heredoc preserves the source file's line endings, and
on CRLF systems that broke `get_env()` substitution in the workload repo's
`root.hcl`. The current form forces LF regardless.

### `OCI_API_KEY_B64` vs `OCI_PRIVATE_KEY_PATH`

The PEM travels as a single-line base64 env var (`OCI_API_KEY_B64`); multi-line
env vars are flaky across shells. In CI the workload repo's
`.github/actions/terragrunt` composite action decodes it to a file and exports
`OCI_PRIVATE_KEY_PATH`. Locally, this stack writes the file and `.envrc` points
at it. Do not use multi-line PEMs as env vars.

### Duplicated `OCI_*` and `TF_VAR_oci_*`

`local.admin_secrets_bundle` and `local.terraform_ci_vars` both emit
`OCI_TENANCY_OCID` *and* `TF_VAR_oci_tenancy_ocid` (same value). Intentional:
the OCI provider reads `OCI_*`, while the workload stacks read the same values
as input variables so their `terraform_remote_state` blocks can authenticate.

### One map, two consumers, and the secret/variable split

`local.terraform_ci_vars` feeds both the GitHub Actions secrets/variables on
`terraform` and the GitLab mirror project's pipeline variables (rollback path).
The two platforms need different classification, so do not share a list:

- `terraform_ci_vars_unmasked` is the GitLab allowlist of values that fail its
  masking rules (single line, at least 8 characters, no `@`). Anything not
  listed is masked.
- `terraform_github_public` lists the values that become Actions *variables*
  rather than secrets (public IDs, the SSH public key, `*_rotated_at`
  timestamps), so GitHub does not redact them from logs. The default is secret.

A new value goes in `terraform_ci_vars`; add it to the matching list only if it
is not sensitive.

### Why this stack owns `terraform`'s repo settings and secrets

A stack must not own the repository, or the credentials, that its own CI runs
from, or an apply could delete what the next run needs to authenticate. This
stack is applied locally, outside CI, so it can always repair what CI stands on.
`terraform/infra` therefore releases `terraform` and does not manage this repo
at all (a stack owning its own housing is the bootstrap paradox). Consequences:

- This repo's `CI_APP_*` Actions secrets are managed by nothing; rotate them by
  hand (see [secret rotation](https://github.com/tnoff/terraform-admin/blob/main/docs/secret-rotation.md#github-app-private-keys)).
- `terraform`'s `TECHDOCS_S3_*` secrets are also not set here.

### Two Discord bot tokens, not one

`discord_bot_token` and `discord_management_token` are two separate Discord
applications. `discord_bot_token` is the live bot's identity and is consumed by
`terraform/apps` (`kubernetes_secret_v1.discord_bot_token`);
`discord_management_token` only lets `terraform/discord`'s provider manage
server structure and never reaches the cluster. Do not point the provider at
the live bot's token, and do not stop pushing `discord_bot_token` to CI without
also removing that Secret: they are coupled. The Cloudflare tokens follow the
same split (`cloudflare_api_token` terraform-only, `cloudflare_dns01_token`
for the in-cluster cert-manager Secret).

## Module sources

Modules come from `github.com/tnoff/terraform-modules`, pinned by commit SHA.
When bumping, bump every `?ref=` in `main.tf` together; Renovate treats each
independently.
