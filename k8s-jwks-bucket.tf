# ==============================================================================
# Hosted key set for the cluster trust (tnoff/terraform#191)
#
# OCI fetches the trust's public_key_endpoint on every new token exchange, so the
# bucket behind it is part of the trust anchor and lives with the trust (it was
# first created by tnoff/terraform oci/ and imported here; the import blocks
# below are the migration and can be dropped once this has been applied).
#
# Anyone who can overwrite jwks.json can mint identities, so the bucket has ONE
# writer: the jwks-publisher CronJob's bot (tnoff/terraform oci/), which uses
# `use objects` on this bucket by name (overwrite only: no create, delete or
# version delete) and only from the cluster network. That is why Terraform seeds
# jwks.json here and ignores later changes to it. No KMS key and no lifecycle
# rules beyond aborting stray uploads: the content is public and tiny, and a
# disabled or deleted key would make it unreadable and break every token
# exchange. Do not put other objects in this bucket or create PARs on it.
# ==============================================================================

# The bucket lives in us-sanjose-1 with the apps; this stack's default provider is
# the home region.
provider "oci" {
  alias               = "sanjose"
  region              = "us-sanjose-1"
  config_file_profile = var.config_file_profile
}

data "oci_identity_compartments" "apps" {
  compartment_id = var.oci_tenancy_ocid
  name           = var.cluster_ci_compartment_name
  state          = "ACTIVE"
}

# The two checkov skips are scoped to this module call, so every other bucket is
# still checked for being private and for a customer-managed key.
module "oidc_jwks_bucket" {
  # checkov:skip=CKV_OCI_10: Public on purpose. OCI Identity Domains must fetch the key set unauthenticated; the content is public key material, listing is off (ObjectReadWithoutList) and writes are limited to one overwrite-only bot (see the comment above).
  # checkov:skip=CKV_OCI_9: No customer-managed key. The content is public and tiny, and a disabled or deleted KMS key would make the key set unreadable and break every token exchange.
  source                         = "git::https://github.com/tnoff/terraform-modules.git//oci/object-storage-bucket?ref=600f00ee56f9b088080b0b4ff7f55f72b7cb5976"
  compartment_ocid               = data.oci_identity_compartments.apps.compartments[0].id
  display_name                   = "k8s_oidc_jwks"
  namespace                      = data.oci_objectstorage_namespace.this.namespace
  access_type                    = "ObjectReadWithoutList"
  versioning_enabled             = true
  archive_after                  = 0
  delete_after                   = 0
  abort_incomplete_uploads_after = 3
  freeform_tags = {
    "ManagedBy" = "terraform"
    "app"       = "oidc-jwks"
    "service"   = "object-storage"
  }
  # Cost-tracking tags; the Billing namespace is owned by tnoff/terraform oci/.
  defined_tags = {
    "Billing.app"     = "oidc-jwks"
    "Billing.service" = "object-storage"
  }
  providers = {
    oci = oci.sanjose
  }
}

# Placeholder so the publisher only ever needs to overwrite. An empty key set
# verifies nothing, so OCI rejects every exchange until the publisher's first run
# replaces it with the cluster's live keys.
resource "oci_objectstorage_object" "oidc_jwks" {
  bucket       = module.oidc_jwks_bucket.bucket.name
  namespace    = data.oci_objectstorage_namespace.this.namespace
  object       = "jwks.json"
  content      = jsonencode({ keys = [] })
  content_type = "application/json"
  provider     = oci.sanjose

  lifecycle {
    ignore_changes = all
  }
}

# Migration from tnoff/terraform oci/ (see the header).
import {
  to = module.oidc_jwks_bucket.oci_objectstorage_bucket.this
  id = "n/${data.oci_objectstorage_namespace.this.namespace}/b/k8s_oidc_jwks"
}

import {
  to = module.oidc_jwks_bucket.oci_objectstorage_object_lifecycle_policy.this[0]
  id = "n/${data.oci_objectstorage_namespace.this.namespace}/b/k8s_oidc_jwks/l"
}

import {
  to = oci_objectstorage_object.oidc_jwks
  id = "n/${data.oci_objectstorage_namespace.this.namespace}/b/k8s_oidc_jwks/o/jwks.json"
}
