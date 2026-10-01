# Development

## Setup

1. Install Terraform `~> 1.9` and Docker (used by the pre-commit hooks).
2. Configure `~/.oci/config` with a profile that has full tenancy access. The
   `DEFAULT` profile is used unless you override `config_file_profile`.
3. Install pre-commit and the hooks:

   ```bash
   pre-commit install
   ```

## Inputs

All inputs (see
[variables.tf](https://github.com/tnoff/terraform-admin/blob/main/variables.tf))
are passed as `TF_VAR_*` environment variables (a gitignored `terraform.tfvars`
also works). The usual pattern is a private file outside the repo that you
source first:

```bash
set -a; . ~/.secrets/terraform-admin.env; set +a
terraform plan
```

Nothing is checked in; every secret lives only in your environment and in the
state file.

## Terraform commands

```bash
terraform init
terraform plan
terraform apply
terraform destroy   # tears down state buckets, IAM, KMS: only if you mean it
```

State is local, at the path configured in
[provider.tf](https://github.com/tnoff/terraform-admin/blob/main/provider.tf),
outside the repo tree. Whatever you back it up to receives the plaintext
secrets in it; see the [security notes](README.md#security-notes).

## Pre-commit and CI

Both hooks in
[.pre-commit-config.yaml](https://github.com/tnoff/terraform-admin/blob/main/.pre-commit-config.yaml)
run in Docker containers so versions are pinned:

- `terraform-fmt`: `hashicorp/terraform fmt -recursive`
- `terraform-docs`: regenerates [terraform.md](terraform.md) in place

```bash
pre-commit run --all-files
pre-commit run terraform-docs --all-files
```

`terraform.md` is generated; never edit it by hand. `.terraform-docs.yml`
disables `lockfile` because `.terraform.lock.hcl` is gitignored and would give
inconsistent provider versions between local and CI.

GitHub Actions run on pull requests: the pre-commit hooks (so a stale
`terraform.md` fails), a trufflehog secret scan, workflow-contract checks and
checkov, with `CI result` as the aggregate. Because the repo is private on a
free plan these checks are advisory (nothing can block a merge). A weekly
workflow runs Renovate and branch cleanup; `techdocs-publish.yml` publishes
`docs/` to Backstage TechDocs. This stack is never applied by CI.

## Adding a workspace state bucket

Append the workspace name to `var.workspaces` in `variables.tf` and apply. The
`terraform_state_buckets` module's `for_each` creates
`terraform-state-<name>` and the KMS policy is extended to cover it. Do this
before the new `terraform` stack's first `init`.

## Rotating credentials

See [docs/secret-rotation.md](https://github.com/tnoff/terraform-admin/blob/main/docs/secret-rotation.md), including how to
regenerate the admin API key (`terraform apply -replace=tls_private_key.terraform_admin`).

## Previewing the docs

```bash
docker run --rm -v "$PWD:/d" -w /d python:3.12-slim sh -c \
  "pip install -q mkdocs-techdocs-core && mkdocs build --strict -d /tmp/site"
```

`docs/README.md`, `AGENTS.md`, `DEVELOPMENT.md`, `CONTRIBUTING.md` and
`terraform.md` are symlinks to the root files so TechDocs can render them.
