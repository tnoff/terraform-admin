# In-cluster workloads to OCI without stored keys

Pods on the OKE cluster call OCI as a **resource principal** instead of holding a
user API key. The cluster is a *basic* OKE cluster, which has no workload identity,
so this is built from parts: the pod's own ServiceAccount token is exchanged at an
OCI Identity Domains trust for a short-lived session token, and an IAM policy per
ServiceAccount decides what that token may do. Tracked in
[tnoff/terraform#191](https://github.com/tnoff/terraform/issues/191), which holds the
history, the experiments behind the rules below and the audit findings.

This stack owns the part everything else rests on: the trust, its exchange app, and the
bucket the trust fetches signing keys from.

## How it fits together

```
 kube-apiserver (private)                    OCI Identity Domains (Default)
   /openid/v1/jwks                             trust "k8s-workloads"
        |                                          ^   fetches the key set on every
        | read by                                  |   NEW exchange (not cached)
        v                                          |
 jwks-publisher CronJob  --overwrite-->  bucket k8s_oidc_jwks / jwks.json  (public read)
 (every 10 min, as a bot)                          ^
                                                   | verifies the ServiceAccount token's
 pod                                               | signature against that key set
  |- rpst sidecar --- token + client creds --------+  and returns an RPST
  |     writes rpst + private.pem to a memory volume
  '- app container: oci SDK get_resource_principals_signer()  ->  OCI API
                                    policy: name + ext_sub + ext_iss  ->  allowed or not
```

The API server is private (reachable only through the bastion), which is why the key
set is mirrored into a public bucket: Identity Domains must fetch it from the internet,
unauthenticated.

| Piece | Lives in | Notes |
|---|---|---|
| Trust `k8s-workloads` and exchange app `k8s-workload-exchange` | this repo, `k8s-oidc-trust.tf` | Separate from the GitHub trust in `oidc-trust.tf`. |
| Bucket `k8s_oidc_jwks` and its seeded `jwks.json` | this repo, `k8s-jwks-bucket.tf` | In us-sanjose-1 (the `sanjose` provider alias). Public read, no listing, versioned. |
| Exchange app credentials to CI | this repo, `main.tf` (`TF_VAR_k8s_exchange_*`) | Reach `terraform` `apps/`. |
| Publisher bot, its API key, the `oke-pods` network source | `terraform` `oci/` | Bot may only overwrite `jwks.json`, only from the cluster network. |
| Per-workload policies (`k8s_workloads`) | `terraform` `oci/` | One policy per ServiceAccount. |
| `rpst-exchange-creds` Secret per namespace | `terraform` `apps/` | Client id and secret of the exchange app. |
| Publisher CronJob | `docker-apps` `apps/jwks-publisher` | Image from `oke-utilities` (`packages/jwks_publisher`). |
| Sidecar | `oke-utilities` `packages/rpst_sidecar` | Run as a native sidecar next to the workload. |

## Why the bucket is the trust anchor

Whoever can change `jwks.json` can add a signing key they control, then mint a
ServiceAccount token for **any** ServiceAccount and exchange it. What that is worth is
bounded by the policies (below), but treat the bucket like a CA bundle:

- **One writer.** The publisher bot has `use objects` on this bucket by name. That
  verb set can overwrite the one seeded object, and cannot create objects, delete,
  delete versions, or create pre-authenticated requests.
- **Network-bound.** The bot's policy also requires `request.networkSource.name =
  'oke-pods'` (a VCN source: Object Storage traffic from the cluster goes through the
  service gateway, so a NAT IP source would not match). A copy of its key used from
  elsewhere is refused.
- **Versioned.** Every change is kept, so a bad write can be reverted.
- **Validated.** The publisher refuses any key that carries private material or is not
  RSA/RS256, and compares before writing.
- **Seeded by Terraform, ignored afterwards.** The object is created here with
  `ignore_changes = all`; the bot only ever overwrites it.
- **Apply identities.** The `oci/` CI apply identity has `manage all-resources` in the
  tenancy (tnoff/terraform#116), so it could also change the bucket. Narrowing it would
  make the bucket stronger; until then this stack (applied only locally) is where the
  trust itself is protected.

Reading `jwks.json` is harmless: it is public key material.

## Policies: what a token can do

A token's identity is matched on three claims. All three are enforced by OCI (verified
on #191):

```
request.principal.name    = 'system:serviceaccount:<namespace>:<serviceaccount>'
request.principal.ext_sub = 'system:serviceaccount:<namespace>:<serviceaccount>'
request.principal.ext_iss = 'https://kubernetes.default.svc.cluster.local'
```

- **`ext_iss` is not optional.** The Kubernetes default issuer string is identical on
  every cluster, and OCI allows one trust per issuer string, so the issuer claim is the
  only thing tying a token to this cluster's trust. The spelling is `ext_iss`;
  `var_ext_iss` does not work.
- **`request.principal.id` is useless.** It is one constant for every Kubernetes
  workload.
- **Use a dedicated ServiceAccount per workload, never `default`.** The policy trusts
  whatever pod runs as that ServiceAccount.
- **No policy, no access.** A ServiceAccount with no entry in `k8s_workloads` gets a
  token that can do nothing. Some list calls (for example `list_compartments`) are open to
  any principal, so do not use those as a "denied" control.

## Onboarding a workload

1. **ServiceAccount.** In `docker-apps`, give the workload its own ServiceAccount with
   `automountServiceAccountToken: false` (the sidecar has its own projected token).
2. **Policy.** In `terraform` `oci/oci.tf`, add an entry to `local.k8s_workloads`
   (`namespace`, `service_account`, `grants` such as `"read metrics in tenancy"`). Keep
   the grants to what the workload needs.
3. **Exchange credentials.** In `terraform` `apps/main.tf`, add the namespace to
   `local.rpst_exchange_namespaces`; that creates the `rpst-exchange-creds` Secret there
   (the namespace must already exist from `bootstrap/` and be covered by its tier map, or
   the apply fails with a Kubernetes 403).
4. **Pod.** Copy the sidecar wiring from `docker-apps`
   `monitoring/oci-monitoring-exporter/deployment.yaml`: the `rpst` native sidecar, the
   memory-backed `emptyDir`, the projected `serviceAccountToken` volume (audience = the
   identity domain URL, 600 s), the `rpst-exchange-creds` volume, and an `fsGroup`. If the
   namespace denies egress, allow the sidecar to reach the identity domain on 443.
5. **App.** Set `OCI_RESOURCE_PRINCIPAL_VERSION=2.2`, `OCI_RESOURCE_PRINCIPAL_RPST`,
   `OCI_RESOURCE_PRINCIPAL_PRIVATE_PEM` and `OCI_RESOURCE_PRINCIPAL_REGION`, and build the
   OCI SDK signer with `get_resource_principals_signer()` once (it re-reads the files as the
   sidecar refreshes them). The app must tolerate the files being absent for a few minutes
   after a policy change and retry rather than crash-loop.
6. **Wait.** New policies and network sources take up to about 10 minutes to take
   effect; the sidecar retries with backoff and logs each failure.
7. **Retire the old key.** Once the workload runs on the new path, remove its user, key,
   policy and Secret in a later change.

## Operating it

**Rebuild or disaster recovery order.** Apply this stack first (the bucket and the trust
are created together). Then `terraform` (`oci/`, then `bootstrap/`, then `apps/`), then
let the publisher CronJob run, then start workloads. Until the publisher's first run
replaces the seeded `{"keys":[]}`, every exchange is rejected.

**What fails how:**

| Situation | Effect |
|---|---|
| Bucket unreachable or `jwks.json` unreadable | New exchanges fail immediately with 401 "Error fetching public key"; tokens already issued keep working until they expire (the sidecar asks for 180 minutes). Recovers within about a second of the bucket coming back. |
| Publisher CronJob not running | Nothing breaks until the cluster rotates its signing key; then new exchanges for tokens signed with the new key fail. The `kube-cronjob-stale` alert fires only after 9 days, so check the last Job. |
| Cluster signing key rotates | The publisher adds the new kid within 10 minutes and logs `added`, `removed`, `kept`. OKE's rotation has not been observed yet; the `jwks-watch` recorder in namespace `jwks-watch` logs the live kids every 12 hours. |
| Sidecar cannot exchange | It retries forever (2 s up to 120 s, with jitter) and its liveness probe (`--check`) restarts it once the token is within a minute of expiry. The app keeps its last token until then. |
| Policy missing or not yet propagated | The exchange succeeds but the app's calls are refused (404 `NotAuthorizedOrNotFound`). |
| Exchange client secret leaks | Not enough on its own: an exchange also needs a ServiceAccount token that the hosted key set verifies. |

**Rotation.**
- The publisher bot's API key rotates with the generation-slot mechanism
  ([runbook in `terraform`](https://github.com/tnoff/terraform/blob/main/docs/generation-slot-rotation.md)).
- The exchange app's client secret has no exercised rotation procedure (see
  [secret rotation](secret-rotation.md)). The sidecar re-reads the mounted Secret on
  every exchange, so a rotated value is picked up without a restart.
- There is nothing to rotate per workload: sessions are minted fresh every refresh.

## Seeing what a workload did

- **Who obtained a token.** The sidecar logs one line per exchange: `jti`, the
  ServiceAccount (the token's `sub`), namespace, pod, issued and expiry. Never the
  tokens themselves.
- **What it did, for writes.** The OCI audit event carries the whole session token in
  `identity.credentials`; decode its payload (no verification needed for reading) to get
  the workload name, `ext_sub`, `ext_iss` and the same `jti`.
- **What it did, for reads.** Reads are audited, but the event does not carry the token:
  `auth_type` is `resource`, `principal_id` is the shared constant, `principal_name` is
  empty and `credentials` is a short placeholder. The caller's **pod IP** is recorded;
  attribute by pod IP and time, matched against the sidecar's exchange log. Repeated
  identical reads did not each appear in the audit log in the one case checked.

## Limits

- Basic OKE clusters only. On an enhanced cluster, use OKE workload identity instead and
  retire this.
- One trust per issuer string. A second cluster with the same default issuer cannot share
  the tenancy's identity domain trust. It would need a distinct service-account issuer,
  which has not been tried on a managed OKE cluster.
- Not used by the cluster autoscaler (it supports only workload identity on enhanced
  clusters, instance principals or an API key file) nor the Grafana-stack S3 keys.

## Checking it is healthy

```sh
# trust exists and points at the bucket
bin/tf output   # or read the trust in the Default domain
# hosted key set is current (kid should match the live cluster)
curl -s https://objectstorage.us-sanjose-1.oraclecloud.com/n/<namespace>/b/k8s_oidc_jwks/o/jwks.json
kubectl get --raw /openid/v1/jwks
# publisher ran recently
kubectl -n jwks-publisher get job
# a workload's sidecar exchanged successfully
kubectl -n <namespace> logs deploy/<workload> -c rpst --tail=5
```
