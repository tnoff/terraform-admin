# ==============================================================================
# IAM Resources - Terraform Admin User
# ==============================================================================

# Generate RSA key pair for Terraform admin user
resource "tls_private_key" "terraform_admin" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# IAM User for managing infrastructure via Terraform
resource "oci_identity_user" "terraform_admin" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Administrative user for managing infrastructure with Terraform"
  name           = var.terraform_admin_user_name

  freeform_tags = {
    "Purpose"   = "terraform-infrastructure-management"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

# API Key for the admin user (for OCI provider)
resource "oci_identity_api_key" "terraform_admin" {
  user_id   = oci_identity_user.terraform_admin.id
  key_value = tls_private_key.terraform_admin.public_key_pem
}

# PEM written to disk because the workload repo's OCI provider auths via
# OCI_PRIVATE_KEY_PATH (env var → file path) — the .envrc below points
# at this exact file. Provider 8.x can also take the literal PEM via
# OCI_PRIVATE_KEY, but multi-line env vars are flaky across shells; the
# file path is single-line and bulletproof.
resource "local_sensitive_file" "terraform_admin_private_key" {
  content         = tls_private_key.terraform_admin.private_key_pem
  filename        = var.terraform_admin_private_key_path
  file_permission = "0600"
}

# Admin group for infrastructure management
resource "oci_identity_group" "terraform_admin" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Administrators group for Terraform infrastructure management"
  name           = var.terraform_admin_group_name

  freeform_tags = {
    "Purpose"   = "terraform-infrastructure-management"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

# Add admin user to admin group
resource "oci_identity_user_group_membership" "terraform_admin" {
  group_id = oci_identity_group.terraform_admin.id
  user_id  = oci_identity_user.terraform_admin.id
}

# Policy for Terraform admin group - full infrastructure management
resource "oci_identity_policy" "terraform_admin" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Administrative policy for Terraform infrastructure management"
  name           = "terraform-admin-policy"

  statements = [
    "Allow group ${oci_identity_group.terraform_admin.name} to manage all-resources in compartment id ${var.oci_tenancy_ocid}",
  ]

  freeform_tags = {
    "Purpose"   = "terraform-infrastructure-management"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

# Policy to allow Object Storage service to use KMS keys for bucket encryption
resource "oci_identity_policy" "admin_kms_object_storage" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Allow Object Storage service to use KMS keys for terraform state buckets"
  name           = "admin-kms-object-storage-policy"

  statements = concat(
    [
      "Allow service objectstorage-${var.oci_region} to use keys in tenancy where target.key.id = '${module.terraform_state_vault.kms_key.id}'",
    ],
    [
      for workspace in var.workspaces :
      "Allow service objectstorage-${var.oci_region} to manage object-family in tenancy where target.bucket.name = '${var.state_bucket_prefix}-${workspace}'"
    ]
  )

  freeform_tags = {
    "Purpose"   = "admin-kms-object-storage-access"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}
