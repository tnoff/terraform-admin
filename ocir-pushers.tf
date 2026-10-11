# ==============================================================================
# OCIR push identities for the image repos (tnoff/terraform#180)
#
# One federated service user per GitHub image repo, so that repo's release workflow
# can push to its OCIR repo(s) with no stored auth token. The job exchanges its GitHub
# OIDC token (docker-push-oidc.yml in tnoff/github-workflows), OCI maps the run to the
# user below, and that user's policy names exactly the OCIR repos it may manage.
#
# Selection is by `sub`, never `aud`: these users can WRITE, and the audience is chosen
# by the job. A push to the repo's main branch has
#   repo:<owner>@<owner id>/<repo>@<repo id>:ref:refs/heads/main
# (immutable subject, so a deleted and recreated repo of the same name cannot inherit
# the identity); a pull request has `...:pull_request` and matches nothing. Enable the
# immutable subject on the repo FIRST, or its tokens carry the name-based form and this
# rule never matches:
#   gh api -X PUT repos/<owner>/<repo>/actions/oidc/customization/sub \
#     -F use_default=true -F use_immutable_subject=true
# `sub` is the calling repo even when the job runs in a reusable workflow from another
# repo, so a shared workflow does not collapse the repos into one identity.
#
# Adding a repo: one entry below, then the usual trust-rule dance (see oidc-trust.tf).
# The old bot user and auth token for the repo are removed from terraform's oci/ stack
# once the first push under this identity is green.
# ==============================================================================

variable "oidc_github_owner" {
  description = "GitHub owner (user or org) of the image repos"
  type        = string
  default     = "tnoff"
}

variable "oidc_github_owner_id" {
  description = "Numeric id of the GitHub owner, for the immutable subject (gh api users/<owner> --jq .id)"
  type        = number
  default     = 1326564
}

locals {
  # key -> the GitHub repo and the OCIR repos its release may push to. github_repo_id is
  # `gh api repos/<owner>/<repo> --jq .id`. ocir_repos are OCIR repository names (the
  # display_name in terraform's oci/ stack), matched exactly by the policy.
  ocir_pushers = {
    magic-mirror-docker = {
      github_repo    = "magic-mirror-docker"
      github_repo_id = 833243768
      ocir_repos     = ["magic-mirror"]
    }
  }

  ocir_pusher_identities = {
    for k, v in local.ocir_pushers : k => merge(v, {
      name = "terraform-ocir-push-${k}-oidc"
      rule = "sub eq repo:${var.oidc_github_owner}@${var.oidc_github_owner_id}/${v.github_repo}@${v.github_repo_id}:ref:refs/heads/main"
    })
  }
}

resource "oci_identity_domains_user" "ocir_pusher" {
  for_each = local.ocir_pusher_identities

  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:User"]
  user_name     = each.value.name
  description   = "Federated service user: the ${each.value.github_repo} release pushes to OCIR (tnoff/terraform#180)"

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }
}

resource "oci_identity_domains_group" "ocir_pusher" {
  for_each = local.ocir_pusher_identities

  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = each.value.name

  members {
    type  = "User"
    value = oci_identity_domains_user.ocir_pusher[each.key].id
  }
}

resource "oci_identity_policy" "ocir_pusher" {
  for_each = local.ocir_pusher_identities

  compartment_id = var.oci_tenancy_ocid
  description    = "Federated push user for the ${each.value.github_repo} image repo: manage its OCIR repos"
  name           = "${each.value.name}-policy"

  statements = [
    "Allow group ${oci_identity_domains_group.ocir_pusher[each.key].display_name} to manage repos in compartment ${var.cluster_ci_compartment_name} where any {${join(", ", [for r in each.value.ocir_repos : "target.repo.name = '${r}'"])}}",
  ]

  freeform_tags = {
    "Purpose"   = each.value.name
    "ManagedBy" = "terraform"
    "Workspace" = "admin"
  }
}
