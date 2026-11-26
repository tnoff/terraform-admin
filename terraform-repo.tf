# Issue-triage labels, same set infra/repos.tf applies to every other GitHub
# repo (local.triage_labels there). Duplicated rather than shared because this
# stack and infra are separate states. Triage is manual -- the untriaged queue
# is a search for open issues without `triaged` -- so keep `triaged` out of
# issue templates, whose `labels:` field applies even for outside reporters.
locals {
  triage_labels = {
    "priority/high"   = "d73a4a"
    "priority/medium" = "fbca04"
    "priority/low"    = "c5def5"
    "triaged"         = "5319e7"
  }
}

# ==============================================================================
# The `terraform` repo itself.
#
# Moved here from terraform/infra on 2026-09-04, because a stack must not own
# the repository its own CI runs from. infra/ is applied BY tnoff/terraform's
# CI, so while infra/ owned that repo an apply could delete the secrets its own
# next run needs to authenticate -- and the fix would have to be applied by the
# CI that could no longer start. Not theoretical: on 2026-09-04 a config that
# had merely fallen behind its state would have destroyed all four OCI_*
# secrets on the next apply. admin is applied locally, outside CI, so it can
# always recover what CI stands on.
#
# It also restores the symmetry the GitLab side always had -- see
# module.terraform_gitlab above, whose comment already claimed admin was "the
# only stack that interacts with the terraform GitLab project".
#
# tnoff/terraform-admin -- THIS repo -- is deliberately NOT here, and is not in
# infra either. A stack owning its own housing is the bootstrap paradox in
# miniature: something has to exist before terraform can run, and for the
# layer-0 stack that something is its own repository, exactly like the local
# state file this stack keeps outside the repo tree. It is created and
# configured by hand.
#
# The cost of that, stated plainly so it is not discovered during a rotation:
# this repo's CI_APP_* Actions secrets are managed by nothing. They were
# written by infra and survive as unmanaged values. When the tnoff-ci App key
# rotates, every other repo picks it up from an apply and THIS one needs:
#
#   gh secret set CI_APP_PRIVATE_KEY --repo tnoff/terraform-admin < key.pem
#
# See var.ci_app_private_key_b64 and time_static.ci_app_private_key_rotated_at.
#
# Only the App credentials are set below. The ~18 values that are genuinely
# "what CI is allowed to know" continue to come from
# github_actions_secret.terraform above, off local.terraform_ci_vars.
#
# No bypass_actors: the module gates its ruleset on `var.is_public &&
# var.enable_ruleset`, and this repo is private, so no ruleset exists for an
# actor to bypass. Rulesets on private repos need GitHub Pro.
module "terraform_repo" {
  source    = "git::https://github.com/tnoff/terraform-modules.git//github/repo?ref=1e3c9cb8b8e75868ea5fe9c4f6be588f3f353972"
  repo_name = "terraform"

  repo_description = "Layer-1 infrastructure: OKE, networking, apps, DNS, Discord and the GitHub/GitLab repo fleet"
  topics           = ["terraform", "terragrunt", "oci", "kubernetes", "infrastructure"]

  # PRIVATE. Every OCID, subnet CIDR, bucket name and cluster detail in the
  # tenancy is in this repo's state and variables.
  is_public  = false
  auto_init  = true
  has_issues = true

  # Public repos get Dependabot alerts unconditionally; private repos need
  # this set explicitly. Free on every plan tier -- checked before landing
  # this, not assumed.
  enable_vulnerability_alerts = true

  repo_labels = local.triage_labels

  # The same three secrets infra writes to every flipped repo, from the same
  # admin inputs infra receives them through.
  action_secrets = {
    CI_APP_ID          = var.ci_app_id
    CI_APP_CLIENT_ID   = var.ci_app_client_id
    CI_APP_PRIVATE_KEY = base64decode(var.ci_app_private_key_b64)
  }
}
