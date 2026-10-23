# ==============================================================================
# TechDocs publish identities (tnoff/terraform#217)
#
# Lets a repo's techdocs-publish workflow write its own docs to the TechDocs bucket with no
# stored key. The job exchanges its GitHub OIDC token exactly as the image push does
# (ocir-pushers.tf): `sub` of a push to main selects a federated service user. The CI key in
# terraform's oci/ stack (backstage_techdocs_ci_creds) is one key that can write the whole
# bucket for every repo; this gives each repo only its own entity prefix.
#
# A repo that already has an OCIR push user (local.ocir_pushers) REUSES that user: a `sub` maps
# to exactly one service user, so a second rule for the same `sub` is not an option. It only gains
# a second policy. Repos without a push user need their own user, group and trust rule first
# (not here yet).
#
# Three statements per repo. `oci os object sync` first does a GetBucket (read buckets, this one
# bucket; OCI answers the denial with a 404 BucketNotFound, which is how it first showed up in
# database-backup's run). OCI cannot scope a LIST by object name, so the workflow lists the entity's
# existing objects with inspect (bucket-wide: names, sizes and hashes, not content) and then
# uploads and deletes stale files with manage, only under default/component/<entity>/.
# ==============================================================================

locals {
  techdocs_bucket_name = "backstage_techdocs"

  # key (must be a key of local.ocir_pushers) -> the Backstage entity name. The bucket path is
  # default/component/<entity>/ (lower case), which is what `techdocs-cli publish --entity`
  # wrote and what the backend reads.
  techdocs_publishers = {
    database-backup = { entity = "database-backup" }
  }
}

resource "oci_identity_policy" "techdocs_publisher" {
  for_each = local.techdocs_publishers

  compartment_id = var.oci_tenancy_ocid
  description    = "Federated ${each.key} release: publish its own TechDocs to the ${local.techdocs_bucket_name} bucket (tnoff/terraform#217)"
  name           = "${local.ocir_pusher_identities[each.key].name}-techdocs-policy"

  statements = [
    "Allow group ${oci_identity_domains_group.ocir_pusher[each.key].display_name} to read buckets in compartment ${var.cluster_ci_compartment_name} where target.bucket.name = '${local.techdocs_bucket_name}'",
    "Allow group ${oci_identity_domains_group.ocir_pusher[each.key].display_name} to inspect objects in compartment ${var.cluster_ci_compartment_name} where target.bucket.name = '${local.techdocs_bucket_name}'",
    "Allow group ${oci_identity_domains_group.ocir_pusher[each.key].display_name} to manage objects in compartment ${var.cluster_ci_compartment_name} where all {target.bucket.name = '${local.techdocs_bucket_name}', target.object.name = 'default/component/${each.value.entity}/*'}",
  ]

  freeform_tags = {
    "Purpose"   = "${local.ocir_pusher_identities[each.key].name}-techdocs"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}
