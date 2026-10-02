# Infrastructure bootstrap and handoff

How `terraform-admin` bootstraps the OCI tenancy and hands credentials to the
`terraform` workload repo. For the list of what this stack creates see the
[README](README.md); for rotating what it holds see
[secret-rotation.md](secret-rotation.md).

## The three repos

- **`terraform-modules`** is a library of reusable Terraform modules (oci,
  kubernetes, cloudflare, discord, github, gitlab). It creates nothing on its
  own. Both other repos consume it through `git::` sources pinned to a commit
  SHA (`?ref=<sha>`), bumped by Renovate.
- **`terraform-admin`** (this repo) is a single Terraform root on **local
  state**, applied by hand and rarely. It creates what everything else needs
  before it can run: the OCI admin user and key, the KMS vault, one state
  bucket per workspace, and the credentials and settings the workload repo's CI
  authenticates with.
- **`terraform`** is the workload: Terragrunt stacks (`oci/`, `discord/`,
  `infra/`, `bootstrap/`, `apps/`, `dns/`) with remote state in the buckets
  created here. Its CI plans on pull requests and applies on merge to `main`,
  except `bootstrap/`, which is operator-applied through a bastion tunnel.

## What this stack provisions

All in the tenancy root compartment (`main.tf`):

- A KMS vault and AES key that encrypt state at rest, with an IAM policy that
  lets Object Storage use the key.
- One versioned, KMS-encrypted bucket per entry in `var.workspaces`, named
  `terraform-state-<workspace>`. The list is the source of truth for which
  stacks have a state backend.
- IAM user `terraform-admin`, group `terraform-administrators`, a tenancy-wide
  manage policy, and a 4096-bit RSA API key for it (private half written to
  `generated-output/terraform_admin_private_key.pem`).
- A tenancy-wide read-only user and key (`mcp-readonly-bot`) for the local OCI
  MCP server.
- The `terraform` repo itself on GitHub (`module.terraform_repo`) and the
  GitHub Actions secrets and variables its CI uses, plus the repo's frozen
  GitLab mirror project and its CI variables (a rollback path only).
- The generated files in `generated-output/` (gitignored): the PEMs, a
  `.envrc`, and the MCP profile.

The admin stack has **no outputs and no remote state**. Nothing reads its
state; the handoff is only through pushed secrets and written files.

## State backend

This stack's backend is **local** (`backend "local"` in `provider.tf`, at a path
outside the repo tree). That is deliberate: it creates the buckets every other
backend uses. Losing the file means losing clean management of the admin user,
KMS key and state buckets, and it holds every secret in plaintext, so back it
up only to an encrypted target such as a restic repository (see the
[README](README.md#security-notes)). It authenticates with your own
`~/.oci/config` profile, not the admin key it creates.

The workload stacks use the OCI backend: `root.hcl` in `terraform` generates
`terraform-state-<stack>` buckets from each directory name in namespace `tnoff`,
region `us-ashburn-1`. State buckets are referenced by name only, so a new
`terraform` stack needs its name added to `var.workspaces` here and an apply
before its backend can initialise.

## Handoff to `terraform`

Two channels carry the same values:

**CI.** `main.tf` builds one map, `local.terraform_ci_vars` (OCI auth, every
`TF_VAR_*` input the stacks need, and the `*_rotated_at` timestamps), and writes
it to the `terraform` repo as `github_actions_secret.terraform` and
`github_actions_variable.terraform`. Anything in `local.terraform_github_public`
(public IDs, the SSH public key, the rotation timestamps) becomes an Actions
*variable* so GitHub does not redact it from logs; everything else is a
*secret*. The same map still feeds GitLab pipeline variables on the mirror
project as a rollback path.

In `terraform`'s workflows the `.github/actions/terragrunt` composite action
exports `TF_VAR_*` and `OCI_*` secrets and variables as environment variables.
It lowercases the `TF_VAR_` suffix (GitHub upper-cases secret names and
terraform's lookup is case-sensitive), base64-decodes `OCI_API_KEY_B64` to a
file, and exports `OCI_PRIVATE_KEY_PATH`. The workflows pass the whole
`secrets`/`vars` context, so a new `TF_VAR_` added here needs no workflow edit.

**Local.** The apply writes `generated-output/.envrc` with export lines for the
same values, plus `OCI_PRIVATE_KEY_PATH` pointing at the PEM on disk. Symlink it
into the workload repo so direnv loads it:

```bash
ln -s ~/Code/terraform-admin/generated-output/.envrc ~/Code/terraform/.envrc
cd ~/Code/terraform && direnv allow
```

Never edit the CI secrets or variables for `tnoff/terraform` by hand; the next
apply here overwrites them. The exceptions are values this stack does not manage,
chiefly `TECHDOCS_S3_*` (see the terraform repo's AGENTS.md) and this repo's own
`CI_APP_*` secrets.

## Bring-up

1. Configure `~/.oci/config` with a profile that can create IAM users, vaults
   and buckets, and export the inputs (see [DEVELOPMENT.md](DEVELOPMENT.md)).
2. In this repo: `terraform init && terraform apply`. Inspect
   `generated-output/`.
3. Symlink the `.envrc` into `terraform` as above.
4. In `terraform`, apply the stacks in order (`terragrunt run --all apply`).
   `apps/`, `dns/` and `bootstrap/` need a live bastion tunnel and the
   `oci-kms` kubeconfig context.

Day to day, workload changes are pull requests to `terraform`, module changes
are pull requests to `terraform-modules` followed by a ref bump, and admin-tier
changes (a new workspace bucket, a new CI secret, a rotated credential) are
edits here applied locally.
