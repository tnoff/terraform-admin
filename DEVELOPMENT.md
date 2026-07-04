# Development

## Setup

1. Install Terraform `~> 1.9` and Docker (used by the pre-commit hooks).
2. Configure `~/.oci/config` with a profile that has full tenancy access. By
   default the `DEFAULT` profile is used; override with the
   `config_file_profile` variable.
3. Install pre-commit and the hooks:

   ```bash
   pre-commit install
   ```

## Inputs

All `TF_VAR_*` inputs (see [variables.tf](variables.tf)) are passed via
environment. The typical pattern is to keep them in a private file outside
the repo and source it before running terraform:

```bash
set -a; . ~/.secrets/terraform-admin.env; set +a
terraform plan
```

There is no `terraform.tfvars` checked in — every secret value lives only in
your environment and in the resulting state file.

## Terraform commands

```bash
terraform init
terraform plan
terraform apply
terraform destroy   # tears down state buckets, IAM, KMS — only if you mean it
```

State is local, written to `~/.local/state/terraform-admin/terraform.tfstate`
(set in [provider.tf](provider.tf)), not the repo tree. That directory is a
symlink to `~/Dropbox/Terraform-Backup/`, so every write is backed up to
Dropbox automatically. Note this means the plaintext secrets in state leave the
machine — see the security notes in [README.md](README.md#security-notes).

## Pre-commit hooks

Configured in [.pre-commit-config.yaml](.pre-commit-config.yaml). Both hooks
run inside Docker containers so they pin exact versions:

- `terraform-fmt` — `hashicorp/terraform:1.11 fmt -recursive`
- `terraform-docs` — `quay.io/terraform-docs/terraform-docs:0.19.0` regenerates
  [terraform.md](terraform.md) in-place

Run all hooks manually:

```bash
pre-commit run --all-files
```

Run just the docs regeneration:

```bash
pre-commit run terraform-docs --all-files
```

## Regenerating terraform.md

`terraform.md` is auto-generated. Never edit it by hand. The
[`.terraform-docs.yml`](.terraform-docs.yml) config disables `lockfile` because
`.terraform.lock.hcl` is gitignored and would produce inconsistent provider
versions between local and CI runs.

## Adding a new workspace bucket

Append the workspace name to `var.workspaces` (default list in
[variables.tf](variables.tf)) and re-apply. The `terraform_state_buckets`
module's `for_each` will create a new `terraform-state-<name>` bucket and the
KMS policy will be extended to cover it.

## Regenerating the admin API key

Taint the TLS key and apply:

```bash
terraform taint tls_private_key.terraform_admin
terraform apply
```

This rotates the OCI API key, rewrites the PEM file, re-encodes
`OCI_API_KEY_B64`, and pushes the new value to GitLab CI variables. Any local
shells using the old `.envrc` need to re-source it.
