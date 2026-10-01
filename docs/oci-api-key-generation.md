# Generate an OCI API signing key (`~/.oci/oci_api_key.pem`)

How to mint a new OCI API signing key pair locally with OpenSSL, wire
it into `~/.oci/config`, and clear the SDK's label warning. Companion to
OCI MCP (mcp-local TechDocs) (the local MCP bot user that consumes such a
key) and generation-slot rotation runbook (terraform TechDocs) (how the **terraform-managed**
service-user keys rotate — a different mechanism, see the split below).

OCI API keys are 2048-bit (minimum) RSA keys in PEM format. The
**private** half stays in `~/.oci`; the **public** half is registered
against the IAM user, and OCI identifies it by an MD5 fingerprint.

## When to use this vs. the generation-slot flow

| Situation | Use |
|---|---|
| Your **personal** CLI/SDK profile, or a throwaway local key | The OpenSSL steps below — generate, upload the public half via the Console, point `~/.oci/config` at the private half. |
| Rotating a **terraform-managed service user** (autoscaler, monitoring-reader, security-scanner, `mcp-readonly-bot`) | generation-slot rotation runbook (terraform TechDocs). The `.pem` is still generated the same way, but the **public key flows through terraform** (`oci_identity_api_key`), never a manual Console upload. |

The key material is generated identically in both cases; only the
**public-key registration path** differs.

## Steps

### 1. Generate the private key

```bash
openssl genrsa -out ~/.oci/oci_api_key.pem 2048
chmod 600 ~/.oci/oci_api_key.pem
```

Use a passphrase-less key for automation/MCP use. Add `-aes256` if you
want it encrypted at rest (you'll then need to supply `pass_phrase` in
`~/.oci/config`).

### 2. Derive the matching public key

```bash
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
```

### 3. Compute the fingerprint

This is the same MD5 fingerprint OCI shows next to the key in the
Console, so you can match them up:

```bash
openssl rsa -pubout -outform DER -in ~/.oci/oci_api_key.pem 2>/dev/null \
  | openssl md5 -c | awk '{print $NF}'
```

### 4. Register the public key

- **Console (personal / manual):** User Settings → API Keys → **Add API
  Key** → paste `~/.oci/oci_api_key_public.pem`. The Console auto-fills
  the fingerprint and offers a ready-made config stanza.
- **Terraform (service user):** feed the public key into the
  `oci_identity_api_key` resource via the generation slot — bump
  `active_generation`, merge, prune. See
  generation-slot rotation runbook (terraform TechDocs). **Do not** hand-upload a
  service-user key in the Console; it will drift from state.

### 5. Point `~/.oci/config` at the private half

```ini
# ~/.oci/config  ([DEFAULT] or your named profile)
fingerprint=<md5-fingerprint-from-step-3>
key_file=~/.oci/oci_api_key.pem
# tenancy=, user=, region= as usual
```

### 6. Clear the `OCI_API_KEY` label warning

The CLI/SDK prints:

> To increase security of your API key located at
> `~/.oci/oci_api_key.pem`, append an extra line with `OCI_API_KEY` at
> the end.

This is a benign convention — the SDK wants the key file "labeled" with
a trailing line containing the literal text `OCI_API_KEY`. It does not
change the key. Two ways to clear it:

**Add the label (what the warning asks for):**

```bash
printf 'OCI_API_KEY\n' >> ~/.oci/oci_api_key.pem
```

The file then ends:

```
-----END PRIVATE KEY-----
OCI_API_KEY
```

The SDK reads the RSA block and ignores the trailing label line, so
signing still works. **Append strictly *after* the `-----END-----`
footer** — a label line placed before it will make stricter parsers
reject the key.

**Or suppress it** (equally fine — it's cosmetic):

```bash
export SUPPRESS_LABEL_WARNING=True   # add to ~/.bashrc to persist
```

## Gotchas

- **Fresh keys 401 for a cycle or two.** Right after upload, a new key
  can return `NotAuthenticated` while IAM propagates the public key.
  This self-heals within ~1 call cycle — don't re-mint on the first 401.
  (See `reference` note *OCI api_key-slot enrollment + transient 401*.)
- **Never label the public key.** Only the private `.pem` you keep
  locally gets the `OCI_API_KEY` line. The public key string is exactly
  what OCI fingerprints — appending to it changes the fingerprint and
  breaks registration. This matters most in the terraform flow, where
  the public key is passed as resource input.
- **Prefer a scoped user + API key over instance-principal auth** for
  this tenancy — workload identity needs enhanced clusters and we run
  basic. (See OCI MCP (mcp-local TechDocs).)

## Cross-references

- System context: OCI MCP (mcp-local TechDocs) (the `mcp-readonly-bot`
  user whose key backs the local OCI MCP server).
- Service-user rotation: generation-slot rotation runbook (terraform TechDocs),
  [secret-rotation.md](secret-rotation.md).

---

## Verified against

| Reference | Detail | Date |
|---|---|---|
| OCI docs | [API signing key concepts](https://docs.oracle.com/iaas/Content/API/Concepts/apisigningkey.htm) | 2026-07-25 |

OpenSSL steps are tool-generic (2048-bit RSA / PEM); the service-user
registration path tracks generation-slot rotation runbook (terraform TechDocs), which
carries its own `Verified against` footer.
