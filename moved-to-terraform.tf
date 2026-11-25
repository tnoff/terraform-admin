# ==============================================================================
# Objects that moved to tnoff/terraform
#
# The GitHub OIDC identity trust, the image-push identities and the TechDocs
# publish identities are no longer managed from here. They are run from CI:
#
#   oci/    the image-push and TechDocs service users, groups and policies
#   trust/  the one GitHub Actions identity-propagation trust
#
# `removed` with destroy = false makes Terraform forget each object WITHOUT
# deleting it in OCI: the live objects keep working and the other repo adopts
# them (import blocks in oci/, `terraform import` for the trust). Apply this
# BEFORE trust/ is applied for the first time, so the two never both own the trust.
#
# Once this has been applied everywhere it can stay: removed blocks are inert once
# the object is out of state.
# ==============================================================================

removed {
  from = oci_identity_domains_identity_propagation_trust.github_actions

  lifecycle {
    destroy = false
  }
}

removed {
  from = oci_identity_domains_user.ocir_pusher

  lifecycle {
    destroy = false
  }
}

removed {
  from = oci_identity_domains_group.ocir_pusher

  lifecycle {
    destroy = false
  }
}

removed {
  from = oci_identity_policy.ocir_pusher

  lifecycle {
    destroy = false
  }
}

removed {
  from = oci_identity_policy.techdocs_publisher

  lifecycle {
    destroy = false
  }
}

removed {
  from = oci_identity_domains_user.techdocs_only

  lifecycle {
    destroy = false
  }
}

removed {
  from = oci_identity_domains_group.techdocs_only

  lifecycle {
    destroy = false
  }
}

removed {
  from = oci_identity_policy.techdocs_only

  lifecycle {
    destroy = false
  }
}
