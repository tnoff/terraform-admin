# Lockout for the identity domain's one human account.
#
# The domain's built-in policies are not assigned to anyone: standardPasswordPolicy
# (5 attempts, 30 minute lockout) has no groups, so the human user falls under
# defaultPasswordPolicy, which has no attempt limit. The 37 service users have no
# passwords. MFA (TOTP) is enrolled on the human account, so a guessed password is
# not enough by itself, but nothing slowed the guessing down.
#
# This adds a custom policy scoped to a group that holds only the human user. The
# built-in policies are left alone (they are seeded by OCI; managing them would
# overwrite their other settings on the first apply).

variable "domain_human_user_name" {
  description = "User name of the domain's human account, which the lockout policy applies to. Not set in the repo so the address is not committed."
  type        = string
}

data "oci_identity_domains_users" "human" {
  idcs_endpoint = local.oidc_domain_endpoint
  user_filter   = "userName eq \"${var.domain_human_user_name}\""
}

resource "oci_identity_domains_group" "human_lockout" {
  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = "human-password-lockout"

  members {
    type  = "User"
    value = data.oci_identity_domains_users.human.users[0].id
  }

  lifecycle {
    precondition {
      condition     = length(data.oci_identity_domains_users.human.users) == 1
      error_message = "domain_human_user_name must match exactly one domain user."
    }
  }
}

resource "oci_identity_domains_password_policy" "human_lockout" {
  idcs_endpoint = local.oidc_domain_endpoint
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:PasswordPolicy"]
  name          = "human-lockout"
  description   = "Lock the human account for 30 minutes after 5 failed sign-ins"
  priority      = 1

  password_strength      = "Standard"
  max_incorrect_attempts = 5
  lockout_duration       = 30

  groups {
    value = oci_identity_domains_group.human_lockout.id
  }
}
