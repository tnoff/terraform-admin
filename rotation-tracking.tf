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

# GitLab admin PAT — used by terraform-admin's gitlab provider.
resource "terraform_data" "gitlab_api_key_version" {
  triggers_replace = [sha256(var.gitlab_api_key)]
}
resource "time_static" "gitlab_api_key_rotated_at" {
  triggers = {
    version = terraform_data.gitlab_api_key_version.id
  }
}

# GitLab token for the tnoff-ci service account — pushed as a CI variable
# on the terraform repo. Renamed from gitlab_bot_api_key(_version/_rotated_at)
# -- moved blocks below preserve the tracked rotation timestamp across the
# rename instead of resetting it via destroy+recreate.
resource "terraform_data" "gitlab_ci_api_key_version" {
  triggers_replace = [sha256(var.gitlab_ci_api_key)]
}
resource "time_static" "gitlab_ci_api_key_rotated_at" {
  triggers = {
    version = terraform_data.gitlab_ci_api_key_version.id
  }
}

moved {
  from = terraform_data.gitlab_bot_api_key_version
  to   = terraform_data.gitlab_ci_api_key_version
}

moved {
  from = time_static.gitlab_bot_api_key_rotated_at
  to   = time_static.gitlab_ci_api_key_rotated_at
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

# tnoff-flux GitHub App private key. Same operator-rotated shape as the
# tnoff-ci key above, and tracked for the same reason that comment gives: an
# untracked long-lived credential is one that has left the age report rather
# than joined it.
#
# It was very nearly left untracked on the argument that an App private key has
# no expiry, so a countdown would never fire. That confuses the two things the
# tracker does. It reports AGE, not just time-to-expiry -- which is exactly the
# signal a credential with no expiry needs, because nothing else will ever
# prompt you to rotate it. The sealed-secrets controller key is the precedent:
# no expiry either, and it carries a deliberate rotate-before date.
#
# This one is Flux's read credential for docker-apps, held in-cluster and used
# unattended every 60s. Rotating means generating a new key in the App's
# settings, updating flux_app_private_key_b64, and re-applying admin then
# bootstrap; the sha256 trigger below restamps the date automatically.
resource "terraform_data" "flux_app_private_key_version" {
  triggers_replace = [sha256(var.flux_app_private_key_b64)]
}
resource "time_static" "flux_app_private_key_rotated_at" {
  triggers = {
    version = terraform_data.flux_app_private_key_version.id
  }
}

# tnoff-backstage GitHub App private key. Same operator-rotated shape as the two
# Apps above, and tracked for the reason the tnoff-flux comment gives: a
# credential with no expiry is exactly the case where an AGE report is the only
# thing that will ever prompt a rotation.
#
# One value, not two. An earlier draft combined this with a client secret; there
# is no client secret, because GitHub App API auth never uses one -- see the
# comment on the bundle entry in main.tf.
resource "terraform_data" "backstage_app_private_key_version" {
  triggers_replace = [sha256(var.backstage_app_private_key_b64)]
}
resource "time_static" "backstage_app_private_key_rotated_at" {
  triggers = {
    version = terraform_data.backstage_app_private_key_version.id
  }
}
