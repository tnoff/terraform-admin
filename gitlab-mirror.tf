# ==============================================================================
# GitLab project mirroring this terraform code (kept for Flux rollback; no CI).
#
# Lives in admin/ (not infra/) because:
#   1. (historical) admin owned the secrets that populated its CI
#      variables; those are gone now, the project runs no CI.
#   2. admin already creates the OCI side of the bootstrap (state buckets,
#      IAM, KMS); creating the GitLab project that uses them belongs in
#      the same layer.
#   3. admin/ is the *only* stack that interacts with the `terraform`
#      GitLab project. infra/ keeps everything else (eastbay, discord-bot,
#      etc.) — those legitimately depend on oci/'s outputs and live
#      downstream.
# ==============================================================================

data "gitlab_group" "personal" {
  full_path = "tnoff-projects"
}

module "terraform_gitlab" {
  source           = "git::https://github.com/tnoff/terraform-modules.git//gitlab/repo?ref=1e3c9cb8b8e75868ea5fe9c4f6be588f3f353972"
  name             = "terraform"
  namespace_id     = data.gitlab_group.personal.id
  visibility_level = "private"

  # The module defaults to "no one", and every repo in infra/repos.tf overrides
  # it to "maintainer"; this one missed that sweep for the same reason the
  # auto_cancel setting below did -- it is managed here rather than there.
  #
  # "no one" was correct while GitLab was canonical: changes arrived by MR, and
  # allowed_to_merge (hardcoded "maintainer" in the module) is a separate gate,
  # so nothing needed direct push. The flip to GitHub inverted that. GitLab
  # `main` is now a mirror target, and github-workflows' fleet-mirror.yml
  # fast-forwards it hourly, pushing as tnoff-ci -- a group Maintainer.
  # "no one" rejects a direct push from *everyone including Owners*, so every
  # run failed with "You are not allowed to push code to protected branches"
  # and alerted #ci-alerts hourly.
  #
  # Raising this does not weaken review on the GitLab side: allowed_to_merge
  # stays "maintainer" and allow_force_push stays false, both hardcoded in the
  # module. GitHub is where the branch protection that matters now lives.
  #
  # Setting it by hand does NOT hold -- this resource is terraform-managed via
  # the module's gitlab_branch_protection.main, so the next apply here reverts
  # it. That is what happened on 2026-09-06: main was raised by hand to land a
  # force-push, and an apply the same evening put it back.
  push_access_level = "maintainer"

  # The module defaults to "enabled", which is what this project has been
  # running. Every repo in infra/repos.tf was set to "disabled" on 2026-07-25;
  # this one missed that sweep only because it is managed here rather than
  # there. With it enabled, a newer pipeline on a ref cancels an older pending
  # one -- and canceled is not failed, so `retry:` never re-runs it and the
  # Grafana gitlab-ci-job-failure alert never fires (GCPE only reads the latest
  # pipeline per ref, so it cannot see the cancelled one either). That matters
  # most here: this is the repo whose main pipelines run apply:*, so a silently
  # cancelled pipeline is an apply that never happened. See
  # docs/findings/2026-07-24-ci-bump-pipeline-autocancel-no-retry.md.
  auto_cancel_pending_pipelines = "disabled"

  schedules = local.terraform_weekly_schedule

  # No pipeline_variables: the GitLab copy is a mirror kept for Flux rollback,
  # not a CI host, so it holds none of local.terraform_ci_vars.
}
