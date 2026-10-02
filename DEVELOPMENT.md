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
also works, but leaves plaintext on disk). The usual pattern is a
gpg-encrypted file outside the repo, decrypted straight into the shell so the
plaintext never touches disk:

```bash
source <(gpg -d ~/.local/state/terraform-admin/.terraform-secrets.sh.gpg)
terraform plan
```

The decrypted file consists of `export TF_VAR_...` lines, so no `set -a` is
needed. To create or edit it, decrypt to a tmpfs path such as `/dev/shm`, edit,
re-encrypt with `gpg --symmetric --cipher-algo AES256 -o ….gpg`, and `shred -u`
the temporary file. Nothing is checked in; every secret lives only in your
environment, the state file and that encrypted file.

## Terraform commands

```bash
terraform init
terraform plan
terraform apply
terraform destroy   # tears down state buckets, IAM, KMS: only if you mean it
```

State is local, at the path configured in
[provider.tf](https://github.com/tnoff/terraform-admin/blob/main/provider.tf),
outside the repo tree. It holds plaintext secrets, so back it up only to an
encrypted target. After every apply (which changes the state and rewrites
`generated-output/`), snapshot it with restic:

```bash
export RESTIC_REPOSITORY=<your restic repo> RESTIC_PASSWORD_FILE=~/.config/restic/pass
restic backup ~/.local/state/terraform-admin
```

`bin/tf` does both steps: it decrypts the inputs into the environment, runs
`terraform` with your arguments, and snapshots the state directory with restic
after any command that can change state (`apply`, `destroy`, `import`,
`state mv|rm|push`, ...), even if terraform fails part-way. It reads the restic
repository from `RESTIC_REPOSITORY` or `~/.config/restic/repository` and the
password from `~/.config/restic/pass`. Set `TF_NO_SECRETS=1` for state/output
commands that need no inputs, or `TF_NO_BACKUP=1` to skip the snapshot.

```bash
bin/tf plan
bin/tf apply
```

See the [security notes](README.md#security-notes).

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
