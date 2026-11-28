# ==============================================================================
# Data Sources
# ==============================================================================

data "oci_identity_tenancy" "current" {
  tenancy_id = var.oci_tenancy_ocid
}

data "oci_objectstorage_namespace" "this" {
  compartment_id = var.oci_tenancy_ocid
}

output "oci_namespace" {
  description = "Object Storage namespace of the tenancy (and of the terraform-state-* buckets). Pushed to terraform as OCI_NAMESPACE: the .envrc and the repo's Actions variables."
  value       = data.oci_objectstorage_namespace.this.namespace
}

# ==============================================================================
# KMS Vault and Encryption Key
# ==============================================================================

module "terraform_state_vault" {
  source = "git::https://github.com/tnoff/terraform-modules.git//oci/secret-vault?ref=1e3c9cb8b8e75868ea5fe9c4f6be588f3f353972"

  compartment_ocid    = var.oci_tenancy_ocid
  display_name        = var.vault_name
  key_shape_length    = 32
  key_shape_algorithm = "AES"
  freeform_tags = {
    "Purpose"   = "terraform-state"
    "ManagedBy" = "terraform"
  }
}

# ==============================================================================
# Runtime secrets vault (tnoff/terraform#341)
# ==============================================================================
# Holds the values that exist only to become Kubernetes Secrets. Written here
# (oci_vault_secret, applied locally), read in-cluster by External Secrets
# Operator as the `eso-reader` user in tnoff/terraform oci/. A separate vault
# from the state one so its IAM and key are not coupled to state encryption.

module "runtime_secrets_vault" {
  source = "git::https://github.com/tnoff/terraform-modules.git//oci/secret-vault?ref=1e3c9cb8b8e75868ea5fe9c4f6be588f3f353972"

  compartment_ocid    = var.oci_tenancy_ocid
  display_name        = var.runtime_secrets_vault_name
  key_shape_length    = 32
  key_shape_algorithm = "AES"
  freeform_tags = {
    "Purpose"   = "runtime-secrets"
    "ManagedBy" = "terraform"
  }
}

output "runtime_secrets_vault_id" {
  description = "OCID of the runtime secrets vault. Pushed to terraform as the TF_VAR_runtime_secrets_vault_ocid Actions variable, for the eso-reader policy in oci/."
  value       = module.runtime_secrets_vault.vault.id
}

output "runtime_secrets_key_id" {
  description = "OCID of the AES key that encrypts the runtime secrets (used by oci_vault_secret)."
  value       = module.runtime_secrets_vault.kms_key.id
}

# ==============================================================================
# Object Storage Buckets (one per workspace)
# ==============================================================================

module "terraform_state_buckets" {
  source                          = "git::https://github.com/tnoff/terraform-modules.git//oci/object-storage-bucket?ref=1e3c9cb8b8e75868ea5fe9c4f6be588f3f353972"
  for_each                        = toset(var.workspaces)
  compartment_ocid                = var.oci_tenancy_ocid
  kms_key_ocid                    = module.terraform_state_vault.kms_key.id
  namespace                       = data.oci_objectstorage_namespace.this.namespace
  display_name                    = "${var.state_bucket_prefix}-${each.key}"
  versioning_enabled              = true
  archive_after                   = 0
  delete_after                    = 0
  abort_incomplete_uploads_after  = 7
  archive_previous_versions_after = 30
  delete_previous_versions_after  = 90
  freeform_tags = {
    "Purpose"   = "terraform-state"
    "ManagedBy" = "terraform"
    "Workspace" = each.key
  }
}
