# ==============================================================================
# Layer-1 rotation tracking
#
# For each admin tfvar whose underlying secret is operator-rotated (not
# managed by terraform itself), capture the apply moment at which its
# value last changed. The `terraform_data` resource is replaced whenever
# the sha256 of the variable value differs from what's in state, which
# in turn triggers replacement of the `time_static` resource — so its
# `rfc3339` attribute is freshly stamped at that moment, then pinned
# until the next value change.
#
# These timestamps flow into the `terraform` GitLab project's CI/CD
# variables as TF_VAR_<name>_rotated_at, are consumed by the apps/
# stack, and are written into the `layer-1-rotation-ledger` ConfigMap
# in the security-scanner namespace where the tracker reads them.
#
# Replaces the operator-maintained `var.layer1_rotation_dates` map —
# rotation tracking is now automatic from the operator's perspective:
# they update the tfvar, re-apply admin/, and the timestamp follows.
#
# Caveat #1: depends on terraform-admin's local state. State loss
# resets every timestamp to the recovery-apply moment. Pre-existing
# risk for the admin tier, but it bites here too.
#
# Caveat #2: first-ever apply stamps every timestamp as "today," so
# the v1 report says nothing is overdue. Treat the first 90d of
# reports as a warm-up period.
#
# See docs/projects/secret-age-tracker.md.
# ==============================================================================

# Discord bot token — also lives in docker-apps/apps/discord/secrets-conf.yaml
# as DISCORD_TOKEN; rotation discipline is to re-seal that file after
# bumping this tfvar.
resource "terraform_data" "discord_token_version" {
  triggers_replace = [sha256(var.discord_token)]
}
resource "time_static" "discord_token_rotated_at" {
  triggers = {
    version = terraform_data.discord_token_version.id
  }
}

# Cloudflare API token — also lives in
# docker-apps/infrastructure/configs/cert-manager/cloudflare-api-key.yaml
# as api-key; rotation discipline is to re-seal that file too.
resource "terraform_data" "cloudflare_api_token_version" {
  triggers_replace = [sha256(var.cloudflare_api_token)]
}
resource "time_static" "cloudflare_api_token_rotated_at" {
  triggers = {
    version = terraform_data.cloudflare_api_token_version.id
  }
}

# GitHub admin PAT — used by terraform's infra stack for repo + mirror
# management. No k8s side, no committed file; ledger is the only signal.
resource "terraform_data" "github_token_version" {
  triggers_replace = [sha256(var.github_token)]
}
resource "time_static" "github_token_rotated_at" {
  triggers = {
    version = terraform_data.github_token_version.id
  }
}

# Renovate bot GitHub PAT — same shape as github_token.
resource "terraform_data" "bot_github_token_version" {
  triggers_replace = [sha256(var.bot_github_token)]
}
resource "time_static" "bot_github_token_rotated_at" {
  triggers = {
    version = terraform_data.bot_github_token_version.id
  }
}

# GitLab admin PAT — used by terraform-admin's gitlab provider.
resource "terraform_data" "gitlab_api_key_version" {
  triggers_replace = [sha256(var.gitlab_api_key)]
}
resource "time_static" "gitlab_api_key_rotated_at" {
  triggers = {
    version = terraform_data.gitlab_api_key_version.id
  }
}

# GitLab bot PAT — pushed as a CI variable on the terraform repo.
resource "terraform_data" "gitlab_bot_api_key_version" {
  triggers_replace = [sha256(var.gitlab_bot_api_key)]
}
resource "time_static" "gitlab_bot_api_key_rotated_at" {
  triggers = {
    version = terraform_data.gitlab_bot_api_key_version.id
  }
}

# OKE worker-node SSH public key. Not a secret per se (just authorized_keys),
# but operator-rotated and worth knowing the last touch.
resource "terraform_data" "ssh_public_key_version" {
  triggers_replace = [sha256(var.ssh_public_key)]
}
resource "time_static" "ssh_public_key_rotated_at" {
  triggers = {
    version = terraform_data.ssh_public_key_version.id
  }
}

# Secret-age tracker's own GitLab read_api PAT — the CronJob that consumes
# rotation timestamps also gets its own timestamp tracked. Recursive but
# useful.
resource "terraform_data" "secret_age_tracker_gitlab_token_version" {
  triggers_replace = [sha256(var.secret_age_tracker_gitlab_token)]
}
resource "time_static" "secret_age_tracker_gitlab_token_rotated_at" {
  triggers = {
    version = terraform_data.secret_age_tracker_gitlab_token_version.id
  }
}

# GCPE (gitlab-ci-pipelines-exporter) read_api PAT — rendered into the
# gcpe-gitlab-token k8s Secret in the monitoring ns by apps/. Same shape as
# secret_age_tracker_gitlab_token above. See docs/projects/gitlab-ci-metrics.md.
resource "terraform_data" "gcpe_gitlab_token_version" {
  triggers_replace = [sha256(var.gcpe_gitlab_token)]
}
resource "time_static" "gcpe_gitlab_token_rotated_at" {
  triggers = {
    version = terraform_data.gcpe_gitlab_token_version.id
  }
}

# tnoff-ci GitHub App private key. Operator-rotated like the PATs above: an
# App key is regenerated from the App's settings page, so nothing here can
# derive its age. Tracked because it is the credential that will replace
# the admin PAT that used to sign CI pushes -- an untracked replacement
# would take a
# long-lived secret off the age report rather than onto it.
resource "terraform_data" "ci_app_private_key_version" {
  triggers_replace = [sha256(var.ci_app_private_key_b64)]
}
resource "time_static" "ci_app_private_key_rotated_at" {
  triggers = {
    version = terraform_data.ci_app_private_key_version.id
  }
}
