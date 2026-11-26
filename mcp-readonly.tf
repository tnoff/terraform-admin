# ==============================================================================
# IAM Resources - MCP Readonly User
#
# Tenancy-wide read-only user backing the local OCI MCP server. Operator-facing
# (not a workload component), so it lives alongside terraform_admin rather than
# in the oci/ workload stack. PEM + ~/.oci/config fragment are written to
# generated-output/ for the operator to paste into ~/.oci/config.
# ==============================================================================

resource "tls_private_key" "mcp_readonly" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "oci_identity_user" "mcp_readonly" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Tenancy-wide read-only user backing the local OCI MCP server"
  name           = var.mcp_readonly_user_name

  freeform_tags = {
    "Purpose"   = "mcp-readonly"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

resource "oci_identity_api_key" "mcp_readonly" {
  user_id   = oci_identity_user.mcp_readonly.id
  key_value = tls_private_key.mcp_readonly.public_key_pem
}

resource "local_sensitive_file" "mcp_readonly_private_key" {
  content         = tls_private_key.mcp_readonly.private_key_pem
  filename        = var.mcp_readonly_private_key_path
  file_permission = "0600"
}

resource "oci_identity_group" "mcp_readonly" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Tenancy-wide read-only group backing the local OCI MCP server"
  name           = var.mcp_readonly_group_name

  freeform_tags = {
    "Purpose"   = "mcp-readonly"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}

resource "oci_identity_user_group_membership" "mcp_readonly" {
  group_id = oci_identity_group.mcp_readonly.id
  user_id  = oci_identity_user.mcp_readonly.id
}

# Pre-formatted ~/.oci/config fragment. Named profile (MCP_READONLY) so it
# composes with any existing DEFAULT block instead of overwriting it.
resource "local_sensitive_file" "mcp_readonly_oci_config" {
  filename        = "generated-output/mcp_readonly_oci_config"
  file_permission = "0600"
  content         = <<-EOT
  [MCP_READONLY]
  user=${oci_identity_user.mcp_readonly.id}
  fingerprint=${oci_identity_api_key.mcp_readonly.fingerprint}
  tenancy=${var.oci_tenancy_ocid}
  region=${var.oci_region}
  key_file=${abspath(var.mcp_readonly_private_key_path)}
  EOT
}

# Policy for MCP readonly group - tenancy-wide read of all resources
resource "oci_identity_policy" "mcp_readonly" {
  compartment_id = var.oci_tenancy_ocid
  description    = "Tenancy-wide read-only policy backing the local OCI MCP server"
  name           = "mcp-readonly-policy"

  statements = [
    "Allow group ${oci_identity_group.mcp_readonly.name} to read all-resources in tenancy",
  ]

  freeform_tags = {
    "Purpose"   = "mcp-readonly"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}
