# Terraform Admin

Bootstrap Terraform configuration for the OCI tenancy that hosts everything
else (the `terraform` workload repo's stacks: `oci/`, `oci-alarms/`, `apps/`,
`discord/`, `dns/`, `infra/`).

## What this creates

- The OCI `terraform-admin` IAM user + API key (used by every other stack
  to auth against OCI)
- The KMS vault + key that encrypts state at rest
- One Object Storage bucket per workload stack (`terraform-state-<stack>`),
  which the other stacks use as their remote state backend
- IAM policies allowing the admin group full management of the tenancy
- The `tnoff-projects/terraform` GitLab project itself (this is the repo
  the workload code lives in), plus every CI/CD variable it uses
- Generated artifacts in `generated-output/`:
  - `oci_config` / `aws_credentials` — for local OCI CLI / S3-compat tools
  - `terraform_admin_private_key.pem` — the admin API key
  - `admin_secrets.json` — bundle of values pushed to GitLab as CI variables
  - `.envrc` — `export VAR=value` lines for every env var the workload
    stacks need, ready for `direnv` or `set -a; . .envrc; set +a`

## Bootstrap pattern

This repo uses **local state** (stored in `terraform.tfstate`) because it
creates the remote state backend that everything else uses. Standard
chicken-and-egg pattern for IaC.

State file is gitignored — keep a backup somewhere. Losing it means losing
the ability to manage the IAM user / KMS key / state buckets cleanly.

## Workload-repo handoff

After `terraform apply` here, the workload repo
(`/home/tnorth/Code/terraform`) gets its auth two ways:

- **In CI**: GitLab CI variables pushed by this stack's `terraform_gitlab`
  module → exposed as env vars in every CI job → before_script decodes
  `OCI_API_KEY_B64` to a file and exports `OCI_PRIVATE_KEY_PATH`.
- **Locally**: source the generated `.envrc` from this repo's
  `generated-output/` into your shell. Simplest setup is a symlink in the
  workload repo so `direnv` picks it up:
  ```sh
  ln -s ~/Code/terraform-admin/generated-output/.envrc ~/Code/terraform/.envrc
  cd ~/Code/terraform && direnv allow
  ```
  Or just `set -a; . ~/Code/terraform-admin/generated-output/.envrc; set +a`
  in each shell.

## Prerequisites

1. OCI CLI configured or API key credentials
2. Terraform >= 1.9
3. Appropriate OCI permissions to create:
   - Object Storage buckets
   - IAM users, groups, and policies

## Initial Setup

### 1. Configure Variables

Copy the example file and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

#### Option A: Use ~/.oci/config (Recommended)

If you already have `~/.oci/config` configured (from OCI CLI setup), just set the compartment:

```hcl
oci_region       = "us-sanjose-1"
compartment_ocid = "ocid1.compartment.oc1..aaaa..."
config_file_profile = "DEFAULT"  # or your profile name
```

The OCI provider will automatically read credentials from `~/.oci/config`.

**Typical ~/.oci/config format:**
```ini
[DEFAULT]
user=ocid1.user.oc1..aaaa...
fingerprint=aa:bb:cc:dd:ee:ff:...
key_file=/home/user/.oci/oci_api_key.pem
tenancy=ocid1.tenancy.oc1..aaaa...
region=us-sanjose-1
```

#### Option B: Explicit Credentials

If you prefer explicit credentials (useful for CI/CD):

```hcl
oci_region       = "us-sanjose-1"
compartment_ocid = "ocid1.compartment.oc1..aaaa..."
tenancy_ocid     = "ocid1.tenancy.oc1..aaaa..."
user_ocid        = "ocid1.user.oc1..aaaa..."
fingerprint      = "aa:bb:cc:dd:ee:ff:..."
private_key_path = "~/.oci/oci_api_key.pem"
config_file_profile = null  # Disable config file
```

### 2. Initialize and Apply

```bash
cd admin
terraform init
terraform plan
terraform apply
```

### 3. Review Outputs

After applying, review the outputs:

```bash
terraform output
```

Important outputs:
- `namespace`: Your OCI Object Storage namespace
- `bucket_name`: Name of the state bucket
- `backend_config_s3`: S3-compatible backend configuration

## Migrating from PostgreSQL to Object Storage

### Current State: PostgreSQL Backend

Your workspaces currently use PostgreSQL:

```hcl
backend "pg" {
  conn_str = "postgres://terraform@localhost/tf_oci?sslmode=disable"
}
```

### Migration Steps

#### Option 1: S3-Compatible Backend (Recommended)

OCI Object Storage supports S3-compatible API, which Terraform supports natively.

For each workspace (`oci`, `apps`, `infra`, `discord`):

1. **Backup current state:**
   ```bash
   cd ../oci  # or apps, infra, discord
   terraform state pull > backup-$(date +%Y%m%d).tfstate
   ```

2. **Update `main.tf` backend block:**

   Replace:
   ```hcl
   backend "pg" {
     conn_str = "postgres://terraform@localhost/tf_oci?sslmode=disable"
   }
   ```

   With (get values from `terraform output -raw backend_config_s3` in admin):
   ```hcl
   backend "s3" {
     bucket                      = "terraform-state"
     key                         = "oci/terraform.tfstate"  # or "apps/", "infra/", "discord/"
     region                      = "us-sanjose-1"
     endpoint                    = "https://<namespace>.compat.objectstorage.us-sanjose-1.oraclecloud.com"
     skip_credentials_validation = true
     skip_metadata_api_check     = true
     skip_region_validation      = true
     force_path_style            = true
   }
   ```

   **Note:** Change the `key` value for each workspace:
   - `oci` workspace: `"oci/terraform.tfstate"`
   - `apps` workspace: `"apps/terraform.tfstate"`
   - `infra` workspace: `"infra/terraform.tfstate"`
   - `discord` workspace: `"discord/terraform.tfstate"`

3. **Configure S3 credentials:**

   OCI uses signature version 4 for S3 API. Set environment variables:
   ```bash
   export AWS_ACCESS_KEY_ID="<OCI_ACCESS_KEY>"
   export AWS_SECRET_ACCESS_KEY="<OCI_SECRET_KEY>"
   ```

   Or create `~/.aws/credentials`:
   ```ini
   [default]
   aws_access_key_id = <OCI_ACCESS_KEY>
   aws_secret_access_key = <OCI_SECRET_KEY>
   ```

   To generate OCI S3 credentials:
   ```bash
   oci iam customer-secret-key create --display-name terraform-state --user-id <USER_OCID>
   ```

4. **Migrate state:**
   ```bash
   terraform init -migrate-state
   ```

   Terraform will prompt:
   ```
   Do you want to copy existing state to the new backend? (yes/no)
   ```

   Type `yes` to migrate.

5. **Verify migration:**
   ```bash
   terraform plan
   ```

   Should show no changes if migration was successful.

6. **Repeat for all workspaces** (`oci`, `apps`, `infra`, `discord`)

#### Option 2: HTTP Backend

OCI Object Storage can also be used with HTTP backend (simpler but less features):

```hcl
backend "http" {
  address       = "https://objectstorage.us-sanjose-1.oraclecloud.com/n/<namespace>/b/terraform-state/o/oci/terraform.tfstate"
  update_method = "PUT"
}
```

Requires OCI CLI configured for authentication.

### Post-Migration Cleanup

After all workspaces are migrated:

1. **Verify all workspaces use Object Storage:**
   ```bash
   cd ../oci && terraform plan
   cd ../apps && terraform plan
   cd ../infra && terraform plan
   cd ../discord && terraform plan
   ```

2. **Optional: Stop PostgreSQL container:**
   ```bash
   docker-compose down
   ```

3. **Optional: Backup PostgreSQL data:**
   ```bash
   docker run --rm -v ~/volumes/terraform/dbdata:/data -v $(pwd):/backup postgres:16 tar czf /backup/postgres-backup-$(date +%Y%m%d).tar.gz /data
   ```

## State Bucket Features

### Versioning

Versioning is **enabled** by default. Every state update creates a new version, allowing rollback if needed.

To list versions:
```bash
oci os object list-object-versions --bucket-name terraform-state --namespace <namespace>
```

To restore a previous version:
```bash
oci os object restore --bucket-name terraform-state --namespace <namespace> --name oci/terraform.tfstate --version-id <version-id>
```

### Lifecycle Management

By default:
- **Archive old versions** after 90 days (saves costs)
- **Deletion disabled** (enable with `enable_state_deletion = true`)

### Encryption

Optional KMS encryption is supported. Set `kms_key_id` variable to use customer-managed encryption.

## IAM Configuration

### Using Existing User/Group

By default, policies are created for the group `terraform-state-access`. Add your existing users to this group:

```bash
oci iam group add-user --group-id <GROUP_OCID> --user-id <USER_OCID>
```

### Creating Dedicated User (CI/CD)

For CI/CD pipelines, create a dedicated user:

```hcl
create_state_user     = true
state_user_name       = "terraform-state-user"
state_user_public_key = "<PUBLIC_API_KEY>"
```

Then use the user's credentials in your CI/CD system.

## Directory Structure

```
admin/
├── main.tf                      # Provider and backend configuration
├── bucket.tf                    # Object Storage bucket and lifecycle
├── iam.tf                       # IAM users, groups, and policies
├── variables.tf                 # Variable definitions
├── terraform.tfvars             # Your values (gitignored)
├── terraform.tfvars.example     # Example values
├── outputs.tf                   # Backend configuration outputs
├── terraform.tfstate            # Local state file (gitignored)
└── README.md                    # This file
```

## Security Considerations

1. **Never commit `terraform.tfstate`** - This file is listed in `.gitignore`
2. **Never commit `terraform.tfvars`** - Contains sensitive credentials
3. **Use KMS encryption** for production state buckets
4. **Enable versioning** to protect against accidental deletion
5. **Restrict bucket access** with IAM policies (NoPublicAccess)
6. **Regular backups** - Export state periodically:
   ```bash
   terraform state pull > backup-$(date +%Y%m%d).tfstate
   ```

## Troubleshooting

### State Lock Issues

OCI Object Storage doesn't natively support state locking. For concurrent runs, consider:
- Using separate state files per workspace (already configured with `key` parameter)
- Implementing external locking with DynamoDB or similar
- Coordinating Terraform runs to avoid conflicts

### S3 API Authentication Errors

If you get S3 authentication errors:
1. Verify credentials are correct: `oci iam customer-secret-key list --user-id <USER_OCID>`
2. Check credentials are exported: `echo $AWS_ACCESS_KEY_ID`
3. Verify user has proper IAM policies (check admin outputs)

### Migration Failures

If migration fails:
1. Check you have backups: `ls backup-*.tfstate`
2. Verify bucket exists and is accessible
3. Check IAM permissions
4. Try migration again - it's safe to retry

## Maintenance

### Updating Lifecycle Policies

Edit `terraform.tfvars`:
```hcl
state_archival_days = 60  # Change from 90 to 60 days
```

Apply changes:
```bash
terraform apply
```

### Adding Users to State Access Group

```bash
oci iam group add-user --group-id $(terraform output -raw state_group_ocid) --user-id <USER_OCID>
```

## References

- [OCI Object Storage Documentation](https://docs.oracle.com/en-us/iaas/Content/Object/home.htm)
- [Terraform S3 Backend](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [OCI S3 Compatibility API](https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/s3compatibleapi.htm)
