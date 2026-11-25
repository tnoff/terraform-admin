# ==============================================================================
# GitHub Environments for applying tnoff/terraform's bootstrap/ from CI
#
# bootstrap/ builds the cluster foundation (namespaces, the RBAC bindings for the
# apps/dns CI groups, the Flux install) and holds the Flux GitHub App private key.
# It is applied from CI behind two Environments, so a pull request can never reach
# its identities or its key:
#
#   bootstrap-plan    main only, no reviewer. The plan job runs here on a push to main.
#   bootstrap-apply   main only, a required reviewer. The apply job waits for approval,
#                     so the reviewer reads the plan job's output first.
#
# What an Environment gives a job:
#   - the job does not start unless the ref passes the branch policy (and, for apply,
#     a reviewer approves), so a pull request branch cannot get anything below;
#   - it receives the Environment's own secrets and variables, which no other job reads;
#   - its OIDC token has sub = repo:<owner>@<id>/<repo>@<id>:environment:<name>, which is
#     what the two bootstrap identities' trust rules match (github-oidc.tf).
#
# The Flux App key is therefore an Environment secret, NOT one of the repo-level secrets
# in main.tf (any workflow job in the repo can read those). Both Environments hold it:
# a plan decodes it to compare with the live Secret. Nothing else in CI needs it.
#
# The `techdocs` Environment (the TechDocs publish rule) was created by hand and is not
# managed here.
# ==============================================================================

locals {
  bootstrap_environments = toset(["bootstrap-plan", "bootstrap-apply"])
}

resource "github_repository_environment" "bootstrap" {
  for_each = local.bootstrap_environments

  repository  = "terraform"
  environment = each.key

  # A single maintainer, so self-review has to be allowed or an apply could never be
  # approved. Revisit if a second reviewer is ever added.
  prevent_self_review = false

  dynamic "reviewers" {
    for_each = each.key == "bootstrap-apply" ? [1] : []

    content {
      users = [var.oidc_github_owner_id]
    }
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_deployment_branch_policy" "bootstrap_main" {
  for_each = local.bootstrap_environments

  repository       = "terraform"
  environment_name = github_repository_environment.bootstrap[each.key].environment
  name             = "main"
}

# The Flux App private key (base64 PEM). Sensitive, so these resources are keyed by
# environment only: a sensitive value cannot be a for_each key or value map.
resource "github_actions_environment_secret" "flux_app_private_key_b64" {
  for_each = local.bootstrap_environments

  repository      = "terraform"
  environment     = github_repository_environment.bootstrap[each.key].environment
  secret_name     = "TF_VAR_flux_app_private_key_b64"
  plaintext_value = var.flux_app_private_key_b64
}

# The App's ids and the key's rotation stamp are identifiers, not credentials.
resource "github_actions_environment_variable" "flux_app_id" {
  for_each = local.bootstrap_environments

  repository    = "terraform"
  environment   = github_repository_environment.bootstrap[each.key].environment
  variable_name = "TF_VAR_flux_app_id"
  value         = var.flux_app_id
}

resource "github_actions_environment_variable" "flux_app_installation_id" {
  for_each = local.bootstrap_environments

  repository    = "terraform"
  environment   = github_repository_environment.bootstrap[each.key].environment
  variable_name = "TF_VAR_flux_app_installation_id"
  value         = var.flux_app_installation_id
}

resource "github_actions_environment_variable" "flux_app_private_key_rotated_at" {
  for_each = local.bootstrap_environments

  repository    = "terraform"
  environment   = github_repository_environment.bootstrap[each.key].environment
  variable_name = "TF_VAR_flux_app_private_key_rotated_at"
  value         = time_static.flux_app_private_key_rotated_at.rfc3339
}
