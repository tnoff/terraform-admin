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
# a second policy. Repos without a push user get their own user, group, trust rule and policy
# from local.techdocs_only_publishers at the bottom of this file.
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
    database-backup     = { entity = "database-backup" }
    eastbay             = { entity = "eastbay" }
    hathor              = { entity = "hathor" }
    magic-mirror-docker = { entity = "magic-mirror-docker" }
    personal-website    = { entity = "personal-website" }
    oke-utilities       = { entity = "oke-scan" } # catalog entity name, not the repo name
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

# ==============================================================================
# Repos that publish TechDocs but push no image (tnoff/terraform#217)
#
# No OCIR push user to reuse, so each gets its own federated service user, group, trust rule and
# policy. Same selection as ocir-pushers.tf: `sub` of the repo, with the immutable subject (enable
# it on the repo FIRST, or the rule never matches):
#   gh api -X PUT repos/<owner>/<repo>/actions/oidc/customization/sub \
#     -F use_default=true -F use_immutable_subject=true
#
# subject_suffix is what follows the repo in `sub`. The default, a push to main, is right for every
# repo here except tnoff/terraform: its apply jobs also run on main, so they share that `sub`, and
# when rules overlap the winner is not decided by list position (github-oidc.tf). Its TechDocs job
# runs in the GitHub environment `techdocs` (techdocs-publish-oidc.yml `environment` input), whose
# `sub` ends in `:environment:techdocs` and matches no apply rule.
#
# prefixes are the bucket prefixes the repo may write, one `manage objects` statement each (OCI
# cannot scope a LIST by object name, so inspect/read stay bucket-wide, as above). The path is
# <namespace>/<kind>/<name> in lower case, which is what techdocs-cli writes. A repo hosting several
# sites (docker-apps) lists every one.
# ==============================================================================

locals {
  techdocs_only_publishers = {
    terraform = {
      github_repo    = "terraform"
      github_repo_id = 1356736164
      subject_suffix = "environment:techdocs"
      prefixes       = ["default/component/terraform"]
    }
    terraform-admin = {
      github_repo    = "terraform-admin"
      github_repo_id = 1356607072
      prefixes       = ["default/component/terraform-admin"]
    }
    terraform-modules = {
      github_repo    = "terraform-modules"
      github_repo_id = 885224619
      prefixes       = ["default/component/terraform-modules"]
    }
    github-workflows = {
      github_repo    = "github-workflows"
      github_repo_id = 1119158120
      prefixes       = ["default/component/github-workflows"]
    }
    public-transit = {
      github_repo    = "public-transit"
      github_repo_id = 30855835
      prefixes       = ["default/component/public-transit"]
    }
    enheduanna = {
      github_repo    = "enheduanna"
      github_repo_id = 926357209
      prefixes       = ["default/component/enheduanna"]
    }
    oci-bastion-keepalive = {
      github_repo    = "oci-bastion-keepalive"
      github_repo_id = 1276219252
      prefixes       = ["default/component/oci-bastion-keepalive"]
    }
    mcp-local = {
      github_repo    = "mcp-local"
      github_repo_id = 1380654231
      prefixes       = ["default/component/mcp-local"]
    }
    docker-apps = {
      github_repo    = "docker-apps"
      github_repo_id = 1357624877
      prefixes = [
        "default/system/backstage",
        "default/system/discord",
        "default/system/hathor",
        "default/system/monitoring",
        "default/system/oke-utilities",
        "default/system/magic-mirror",
        "default/system/tyler-north-com",
        "default/system/eastbay-massage",
        "default/component/cert-manager",
        "default/component/docker-apps",
      ]
    }
  }

  techdocs_only_identities = {
    for k, v in local.techdocs_only_publishers : k => merge(v, {
      name = "terraform-techdocs-${k}-oidc"
      rule = "sub eq repo:${var.oidc_github_owner}@${var.oidc_github_owner_id}/${v.github_repo}@${v.github_repo_id}:${lookup(v, "subject_suffix", "ref:refs/heads/main")}"
    })
  }
}

resource "oci_identity_domains_user" "techdocs_only" {
  for_each = local.techdocs_only_identities

  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User"]
  user_name     = each.value.name
  description   = "Federated service user: the ${each.value.github_repo} TechDocs publish writes its own docs to the ${local.techdocs_bucket_name} bucket (tnoff/terraform#217)"

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }
}

resource "oci_identity_domains_group" "techdocs_only" {
  for_each = local.techdocs_only_identities

  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = each.value.name

  members {
    type  = "User"
    value = oci_identity_domains_user.techdocs_only[each.key].id
  }
}

resource "oci_identity_policy" "techdocs_only" {
  for_each = local.techdocs_only_identities

  compartment_id = var.oci_tenancy_ocid
  description    = "Federated ${each.key} TechDocs publish: write its own prefixes in the ${local.techdocs_bucket_name} bucket (tnoff/terraform#217)"
  name           = "${each.value.name}-policy"

  statements = concat(
    [
      "Allow group ${oci_identity_domains_group.techdocs_only[each.key].display_name} to read buckets in compartment ${var.cluster_ci_compartment_name} where target.bucket.name = '${local.techdocs_bucket_name}'",
      "Allow group ${oci_identity_domains_group.techdocs_only[each.key].display_name} to inspect objects in compartment ${var.cluster_ci_compartment_name} where target.bucket.name = '${local.techdocs_bucket_name}'",
    ],
    [
      for p in each.value.prefixes :
      "Allow group ${oci_identity_domains_group.techdocs_only[each.key].display_name} to manage objects in compartment ${var.cluster_ci_compartment_name} where all {target.bucket.name = '${local.techdocs_bucket_name}', target.object.name = '${p}/*'}"
    ],
  )

  freeform_tags = {
    "Purpose"   = "${each.value.name}-techdocs"
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}
