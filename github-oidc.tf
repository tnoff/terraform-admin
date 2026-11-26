# ==============================================================================
# Objects that moved to tnoff/terraform
#
# The per-stack plan and apply identities (14 domain users, groups and policies, one pair
# per stack) are managed by tnoff/terraform oci/ (federation-stacks.tf), which publishes their
# trust rules as the stack_oidc_rules output for trust/. The cluster RBAC bindings look the
# groups up by name, so admin no longer publishes their OCIDs or the rule list.
#
# `removed` with destroy = false makes Terraform forget each object WITHOUT deleting it in
# OCI: the live objects keep working and oci/ adopted them by import. Apply this once; the
# file can be deleted after that, since removed blocks are inert once the objects are out of
# state.
# ==============================================================================

removed {
  from = oci_identity_domains_user.oidc

  lifecycle {
    destroy = false
  }
}

removed {
  from = oci_identity_domains_group.oidc

  lifecycle {
    destroy = false
  }
}

removed {
  from = oci_identity_policy.oidc

  lifecycle {
    destroy = false
  }
}
