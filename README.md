# Terraform Admin

Bootstrap Terraform configuration for the OCI tenancy that hosts everything else
(the `terraform` workload repo's stacks: `oci/`, `apps/`, `discord/`, `dns/`,
`infra/`, plus the operator-run `bootstrap/`).

## What this creates

- The OCI `terraform-admin` IAM user, group, policy, and API key (used by every
  other stack to auth against OCI)
- A KMS vault + key that encrypts state at rest
- One Object Storage bucket per entry in `var.workspaces`
  ([variables.tf](variables.tf) — that list is the source of truth for which
  stacks have a bucket, `terraform-state-<workspace>`), used as the remote
  state backend by the other stacks
- Every CI/CD credential the `terraform` workload repo's CI uses — pushed to
  its GitHub Actions secrets/variables (the live path, since it went
  GitHub-canonical) and to its `tnoff-projects/terraform` GitLab project's CI
  variables (kept as a rollback path; see [AGENTS.md](AGENTS.md))
- The GitLab project resource itself (branch protection, mirror settings) —
  not the code's canonical home anymore, just a mirror `github-workflows`'
  `fleet-mirror.yml` keeps in sync
- Generated artifacts in `generated-output/` (gitignored):
  - `terraform_admin_private_key.pem` — the admin API key
  - `.envrc` — `export VAR=value` lines for every env var the workload stacks
    need, ready for `direnv` or `set -a; . .envrc; set +a`

## Bootstrap pattern

This repo uses **local state** because it creates the remote state backend that
everything else uses. Standard chicken-and-egg pattern for IaC.

State lives outside the repo tree (see [provider.tf](provider.tf) for the
configured path) so it can't be committed or wiped by `git clean`. Back it up
yourself — losing it means losing the ability to manage the IAM user / KMS
key / state buckets cleanly. See [Security notes](#security-notes) for what
the file contains and why that matters for whatever backup target you pick.

## Workload-repo handoff

After `terraform apply` here, the workload repo (`~/Code/terraform`) gets its
auth two ways:

- **In CI**: GitHub Actions secrets/variables pushed by
  `github_actions_secret.terraform` / `github_actions_variable.terraform` →
  exposed as env vars via `terraform`'s `.github/actions/terragrunt`
  composite action, whose "Materialise the OCI API key" step decodes
  `OCI_API_KEY_B64` to a file and exports `OCI_PRIVATE_KEY_PATH`. The same
  values also still reach `terraform`'s GitLab CI variables (the
  `terraform_gitlab` module's `pipeline_variables`), but only as a rollback
  path — `terraform` went GitHub-canonical on 2026-09-04 and its
  `.gitlab-ci.yml` no longer exists.
- **Locally**: source the generated `.envrc` from `generated-output/` into
  your shell. Simplest setup is a symlink in the workload repo so `direnv`
  picks it up:

  ```sh
  ln -s ~/Code/terraform-admin/generated-output/.envrc ~/Code/terraform/.envrc
  cd ~/Code/terraform && direnv allow
  ```

  Or `set -a; . ~/Code/terraform-admin/generated-output/.envrc; set +a` in
  each shell.

## Prerequisites

- Terraform >= 1.9
- OCI CLI configured at `~/.oci/config` with a profile that can create IAM
  users, KMS vaults, and Object Storage buckets in the target tenancy
- A GitLab personal access token with `api` scope (provided via
  `TF_VAR_gitlab_api_key`)
- Four GitHub Apps already created (`tnoff-terraform`, `tnoff-ci`,
  `tnoff-flux`, `tnoff-backstage`) with their IDs/keys on hand — see
  [variables.tf](variables.tf) for what each replaces and why they're
  separate Apps rather than one

## Usage

Inputs are passed as `TF_VAR_*` environment variables (no checked-in tfvars
file). See [variables.tf](variables.tf) for the full, current list — it is
the source of truth; the grouping below is current as of this writing but
will drift, same as the previous version of this list did:

- `oci_tenancy_ocid`
- `cloudflare_api_token`, `cloudflare_dns01_token`, `cloudflare_account_id`
- `discord_bot_token`, `discord_management_token`
- `terraform_app_id`, `terraform_app_installation_id`,
  `terraform_app_private_key_b64`
- `flux_app_id`, `flux_app_installation_id`, `flux_app_private_key_b64`
- `backstage_app_id`, `backstage_app_client_id`,
  `backstage_app_private_key_b64`
- `ci_app_id`, `ci_app_client_id`, `ci_app_private_key_b64`
- `gitlab_api_key`, `gitlab_ci_api_key`, `gitlab_ci_service_account_id`
- `ssh_public_key`
- `sealed_secrets_tls_crt_b64`, `sealed_secrets_tls_key_b64`

Apply:

```bash
terraform init
terraform plan
terraform apply
```

After apply, `generated-output/.envrc` and
`generated-output/terraform_admin_private_key.pem` are written to disk. Both
are sensitive — do not commit.

## Security notes

- The state file is gitignored and kept outside the repo tree (not committed,
  not wiped by `git clean`). It holds the **unencrypted** admin private key and
  all sensitive `TF_VAR_*` values pushed to GitHub Actions and GitLab CI —
  treat any backup or sync target for it with the same care you'd give those
  credentials directly.
- ⚠️ If you back this state up anywhere (cloud sync, another disk, etc.), the
  plaintext secrets above travel with it. Prefer an encrypted target (e.g.
  git-crypt, restic, or an encrypted volume) over a general-purpose sync
  unless you already trust that destination with these credentials directly.
  Acceptable to relax this only for a personal, single-user tenancy; do not
  replicate for shared/production state.
- State buckets have versioning enabled. Old versions archive after 30 days
  and are deleted after 90.
- KMS encryption is applied to every state bucket via the `terraform-state`
  vault. The Object Storage service is granted use of the key via
  `admin-kms-object-storage-policy`.

## Auto-generated reference

[terraform.md](terraform.md) is generated by [terraform-docs](https://terraform-docs.io/)
and lists every input, output, resource, and module. Do not edit by hand — the
pre-commit hook will overwrite it. See [DEVELOPMENT.md](DEVELOPMENT.md) for how
to regenerate.
