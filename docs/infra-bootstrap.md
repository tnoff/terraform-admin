# Infrastructure bootstrap & deployment

How `terraform-modules`, `terraform-admin`, and `terraform` work together to
provision and operate the OCI tenancy.

## TL;DR

- **terraform-modules** is a pure library of reusable Terraform modules
  (oci, kubernetes, cloudflare, discord, github, gitlab). It produces no
  infrastructure on its own.
- **terraform-admin** is a single-root bootstrap with **local state**. Run
  rarely, run locally. It creates the OCI tenancy scaffolding that everything
  else depends on: the IAM admin user, the KMS vault, the state buckets, and
  the `terraform` GitLab project itself (including all its CI/CD variables).
- **terraform** is the workload, organized as Terragrunt stacks (`oci/`,
  `discord/`, `infra/`, `bootstrap/`, `apps/`, `dns/`). Remote state lives in
  the OCI buckets created by terraform-admin. CI plans on MR, auto-applies on
  `main` — except `bootstrap/`, which is operator-run (see the callout under
  *Operational flow*).
  (The `oci-alarms/` stack was decommissioned — OKE alarms re-authored in
  Grafana, ONS topic removed — and its state bucket was dropped from
  `var.workspaces` on 2026-09-20.)

## Roles

### terraform-modules — the library
- **Consumption pattern:**
  `source = "git::https://gitlab.com/tnoff-projects/terraform-modules.git//<provider>/<module>?ref=<commit-sha>"`
- **Versioning:** SHA-pinned, not tag-pinned. One stale `v0.0.1` tag exists
  but isn't used; Renovate manages SHA bumps.
- **Load-bearing modules:**
  - OKE networking is **three single-purpose modules** — `oci/oke-vcn`
    (VCN + gateways + route tables), `oci/oke-security-lists` (all security
    lists from per-role CIDR lists), and `oci/oke-subnet` (one subnet per
    instantiation). There is **no `oke-networking` facade module** anymore;
    `oci/oke-networking` is now just a composition-recipe README (its
    `main.tf`/`outputs.tf` were removed). The live `terraform` `oci/` stack
    composes the three directly (`vcn → security-lists → subnets`), and their
    outputs feed `oci/oke-cluster`, `oci/oke-node-pool`, and `oci/bastion`.
  - `oci/oke-node-pool` — embeds a templated cloud-init that runs
    `oci-growfs`, tunes kubelet image-GC, and caps `oracle-cloud-agent-updater`
    memory. Must include the default OKE init script or nodes won't join. See
    runbooks under `terraform-modules/oci/docs/`.
  - `oci/iam-user` — single-value auth token / API key / customer secret
    key per user. `enable_api_key` (added `836c49d`) force-creates the API
    key when `user_public_key` is sourced from a sibling resource
    (plan-time unknown). A slot-based rotation variant exists on the
    `feat/iam-user-credential-rotation-slots` branch but has not been
    merged; main still requires resource recreation for credential
    rotation.
  - `oci/secret-vault`, `oci/object-storage-bucket`, `oci/kms-policies` — the
    primitives `terraform-admin` composes for the state-backend setup.
- **CI does no release/tag step** — just fmt, validate, terraform-docs check,
  trufflehog, Discord notify, Renovate.

### terraform-admin — the bootstrap
- **State strategy:** local backend by design (`backend "local"` in
  `provider.tf`). Gitignored. Chicken-and-egg: this is the root that creates
  the state buckets every other root uses.
- **What it provisions** (all in the root compartment, single flat root in
  `main.tf`):
  - KMS vault + AES-256 key for state encryption.
  - One Object Storage bucket per workspace, name = `terraform-state-<workspace>`,
    KMS-encrypted, versioning on. Workspaces are
    `[discord, infra, oci, bootstrap, apps, dns]` (the
    `bootstrap` bucket backs the operator-run cluster-foundation stack).
  - IAM user `terraform-admin`, group `terraform-administrators`,
    `manage all-resources` policy at the tenancy.
  - KMS-use policy for the `objectstorage-<region>` service.
  - 4096-bit RSA API key for the admin user, private half written to
    `generated-output/terraform_admin_private_key.pem`.
  - The `tnoff-projects/terraform` GitLab project itself, ~18 CI/CD
    variables on it, and a weekly pipeline schedule.
- **Auth:** OCI config-file profile (`~/.oci/config`) — runs under the
  operator's own identity.
- **State recovery:** losing `terraform.tfstate` means losing clean
  management of the admin user, KMS key, and state buckets. Backups matter.

### terraform — the workload
- **Orchestrator:** Terragrunt. Each top-level directory is a stack
  containing one Terraform root and a thin `terragrunt.hcl` that includes
  `root.hcl` from the repo root.
- **Backend:** `root.hcl` generates an OCI Object Storage backend per stack:
  bucket `terraform-state-${local.stack}`, namespace `tnoff`, region
  `us-ashburn-1`, auth via the admin user's API key.
- **Stacks (what each one deploys):**
  - `oci/` — IAM, compartments, OKE cluster, OCIR, buckets, KMS.
  - `discord/` — Discord server, roles, channels, webhooks.
  - `infra/` — GitHub + GitLab repo management, GitHub Actions secrets,
    GitHub→Discord webhooks.
  - `bootstrap/` — the operator-run cluster-foundation stack: namespaces,
    `flux-system-https`, the Flux install (Flux Operator + FluxInstance), and the
    sealed-secrets controller key Secret. It also owned the `terraform-apps` SA/RBAC
    until 2026-09-04, when that identity was retired. **Not** applied in CI — see the
    callout under *Operational flow*.
  - `apps/` — Kubernetes secrets written into namespaces created by
    Flux from `docker-apps`: OCIR pull secrets (`oci-docker-cfg`),
    Object Storage creds for the discord/grafana database backup jobs
    and monitoring, Grafana SA tokens (`mcp-grafana`), GitLab PATs
    (`mcp-gitlab`), security scanner OCI creds, and GitLab Runner
    registration tokens. See workload deployment (docker-apps TechDocs).
  - `dns/` — Cloudflare DNS records pointing at the OKE ingress LB IPs.
    Reads the dynamic NLB IP from the `ingress-nginx` service deployed by
    `docker-apps`. See workload deployment (docker-apps TechDocs).
- **Module consumption:** all external sources are git refs to
  terraform-modules at full commit SHAs. Currently four different SHAs
  are in flight across the repo (most `oci/*` on one,
  discord/cloudflare/github/k8s on another, `gitlab/repo` on a third,
  and `oci/iam-user` for the security-scanner bot on a fourth) —
  expected churn from per-module Renovate updates.

## Tags & labels

Provenance metadata is stamped on everything the workload stacks create, so
terraform-owned resources are distinguishable and cost-attributable. Each
layer keeps one shared local instead of per-resource literals:

- **OCI (`oci/`)** — `local.common_freeform_tags = { ManagedBy = "terraform" }`
  is merged onto every taggable resource
  (`merge(local.common_freeform_tags, { app = ..., service = ... })`).
  Billable resources additionally carry `defined_tags` from the `Billing`
  cost-tracking namespace (`Billing.app`, `Billing.service`,
  `is_cost_tracking = true`). Coverage is 100% of taggable types — including
  the `oci_identity_policy` resources in the `kms-policies` /
  `object-storage-lifecycle-policies` modules, which gained a `freeform_tags`
  variable specifically so they could be tagged.
- **Kubernetes (`apps/`)** — `local.common_labels =
  { "app.kubernetes.io/managed-by" = "terraform" }` is set on the
  `metadata.labels` of every rendered Secret and ConfigMap. Pure inventory
  metadata, not a selector; rotation timestamps stay *annotations*
  (see custom annotation keys (docker-apps TechDocs)).
- **GitLab (`infra/`)** — MR labels are IaC, not auto-created:
  - `gitlab_group_label.dependencies` on the `tnoff-projects` group — every
    project inherits it, so Renovate MRs (which request `dependencies` via the
    shared `github-workflows//renovate/default` preset) land with a
    consistently-defined label instead of a per-project auto-created one.
  - `gitlab_project_label.docker_apps_image_bump` — the docker-apps-only
    tag-bump label (project-scoped, not a group standard).

**Gotcha — adopting a pre-existing label:** GitLab auto-creates a project
label the first time automation applies it, so a plain `gitlab_project_label`
create 409s on an already-existing one. Adopt it with an `import {}` block
whose id is `{project_id}:{numeric_label_id}` (the numeric label id, not the
name — read it from `glab api "projects/<enc>/labels"`). The MR's
`plan:<stack>` job evaluates the import against the live label, so a green
plan proves the id format; expect `Plan: 1 to import, 1 to add, N to change`
(the change is usually just a `description` the auto-created label lacked).

## Handoff between terraform-admin and terraform

There is **no `terraform_remote_state`** linkage between the two repos. The
handoff is two-channel:

1. **CI channel.** terraform-admin pushes OCI auth material and other
   secrets directly into `terraform`'s GitHub Actions secrets/variables
   (`github_actions_secret.terraform`, the live path since `terraform` went
   GitHub-canonical on 2026-09-04) and, as a rollback path only, into the
   `terraform` GitLab project as CI/CD variables via its `gitlab` provider. The workload CI's `before_script` base64-decodes
   `OCI_API_KEY_B64` to a PEM file and exports `OCI_PRIVATE_KEY_PATH`.
   → **Never set CI variables manually in the GitLab UI for `terraform`** —
   they'll be overwritten on the next `terraform apply` in terraform-admin.

2. **Local channel.** terraform-admin writes `generated-output/.envrc`
   (export lines for `OCI_*`, `TF_VAR_*`, etc.) and
   `generated-output/terraform_admin_private_key.pem`. The convention is to
   symlink that `.envrc` into `~/Code/terraform/.envrc` so direnv picks it up
   when running Terragrunt locally.

State buckets are referenced by name only — `root.hcl` builds the bucket
name from the stack's directory name. If you add a new stack to `terraform`
you must also add it to `var.workspaces` in terraform-admin and re-apply,
or the backend will fail to find its bucket.

## Operational flow

```
terraform-modules (library, no state)
        │
        ├──── consumed by ────▶  terraform-admin (local state, run rarely)
        │                              │
        │                              │ creates: buckets, IAM user, KMS,
        │                              │          GitLab CI variables
        │                              ▼
        └──── consumed by ────▶  terraform (remote state in OCI buckets)
                                       │
                                       │ apply DAG (serial in CI):
                                       ▼
                  oci  →  discord  →  infra  →  apps  →  dns
```

~~CI runner split: `oci`, `discord`, and `infra` run on the default `self-hosted`
runner with API-key auth. `dns` and `apps` need in-cluster Kubernetes API access, so they
run on a separate ref-protected `oke-elevated` runner as the `terraform-apps`
ServiceAccount inside OKE.~~

**Superseded 2026-09-04. There is no runner split, and no self-hosted runner.** All five
stacks run on GitHub-hosted runners (`.github/workflows/{ci,apply}.yml`). `oci`,
`discord` and `infra` need only API-key auth, as before. `dns` and `apps` open an **OCI
Bastion port-forwarding session** to the cluster's private API endpoint and write a
CA-pinned kubeconfig at `~/.kube/config` with context `oci-kms` — which is exactly where
their kubernetes provider already looked when no in-cluster token is present, so neither
stack needed a terraform change. The `terraform-apps` ServiceAccount is deleted; CI
authenticates as the CI OCI user, which OKE's webhook authorizer maps to cluster-admin.

> **Shipped 2026-07-13** (SA/RBAC removed 2026-09-04). The `bootstrap` stack owns
> namespaces + ~~the `terraform-apps` SA/RBAC +~~ Flux install + the sealed-secrets controller key
> Secret (seeded from the single consolidated key, held as
> `sealed_secrets_tls_{crt,key}_b64` tfvars sourced via the operator's `.envrc`
> only — see [`projects/sealed-secrets-key-bootstrap.md`](https://github.com/tnoff/docs/blob/main/projects/sealed-secrets-key-bootstrap.md)), so the cluster
> foundation is reproducible from terraform instead of a manual `flux
> bootstrap`. Because the OKE API is private and the only runners are
> in-cluster (Flux-deployed), `bootstrap` **cannot run in CI** — it is
> **operator-run locally via the bastion tunnel + `oci-kms` kubeconfig**
> (the same path the first `apps`/`dns` apply uses). Cold-start becomes an
> operator-run local sequence `oci → infra → bootstrap`, then Flux brings up
> the in-cluster runners and `apps`/`dns` take over in CI. The `oci-kms`
> admin identity is independent of the scoped SA, which is why `bootstrap`
> can create the very SA `apps` later runs as. See
> repo ownership boundary (docker-apps TechDocs),
> [`projects/cluster-bootstrap-stack.md`](https://github.com/tnoff/docs/blob/main/projects/cluster-bootstrap-stack.md), and cluster access (oci-bastion-keepalive TechDocs) (bastion).

### Initial bring-up

1. Set up `~/.oci/config` with the bootstrap operator's profile.
2. In `terraform-admin/`: `terraform init && terraform apply`. Inspect
   `generated-output/`.
3. Symlink `~/Code/terraform-admin/generated-output/.envrc` →
   `~/Code/terraform/.envrc`.
4. In `terraform/<stack>/`: `terragrunt init && terragrunt apply`, in DAG
   order.

### Day-to-day

- **Workload change:** MR to `terraform`. CI plans on MR, auto-applies on
  merge to `main`.
- **Module change:** MR to `terraform-modules`. Renovate (or a manual MR)
  then bumps the `?ref=<sha>` pins in `terraform`.
- **Admin-tier change** (new workspace, new CI variable, rotated secret):
  edit `terraform-admin/`, apply locally.

## Gotchas worth knowing

- **`terraform-modules/README.md` provider table is stale** — claims OCI
  `~> 6.20`; actual modules pin `~> 8.0`. (The module index does now list
  `gitlab/repo`.)
- **Four different terraform-modules SHAs** currently coexist in
  `terraform` (one even within `oci/` itself, where the security-scanner
  bot user lags the rest). This is normal under per-module Renovate but
  worth knowing before chasing "why is this ref different from that ref."
- **`terraform-admin` has no outputs** — all handoff is via written files
  and pushed CI variables, not `terraform_remote_state`.
- **`oci/oke-node-pool` cloud-init is load-bearing** — see the runbooks at
  `terraform-modules/oci/docs/` (disk pressure, OSMS memory). The IAM
  rotation runbook only exists on the unmerged
  `feat/iam-user-credential-rotation-slots` branch.

---

## Verified against

| Project | SHA | Date |
|---|---|---|
| `terraform` | `eaa9770` | 2026-07-14 |
| `terraform-admin` | `63ad554` | 2026-07-14 |
| `terraform-modules` | `f77e71e` | 2026-07-14 |

*Related: workload deployment (docker-apps TechDocs) (Flux GitOps on top of the cluster this
layer provisions), image promotion (docker-apps TechDocs) (producer → consumer image bumps
that use the CI trigger token created here).*
