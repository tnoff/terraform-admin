# ==============================================================================
# Objects that moved to tnoff/terraform
#
# The in-cluster ServiceAccount token-exchange app (k8s-workload-exchange), its secret-version
# helper and its rotation stamp are managed by tnoff/terraform trust/ (k8s-workloads.tf), next
# to the k8s-workloads trust that lists it, so a rotation is one stack. apps/ reads the client
# id, secret and rotation date from trust/'s state. The GitHub exchange app (oidc-exchange.tf)
# is NOT moved: it is CI's own login and stays here with the credentials.
#
# `removed` with destroy = false makes Terraform forget each object WITHOUT deleting it in
# OCI: the live app keeps working. Apply this once; the file can be deleted after that, since
# removed blocks are inert once the objects are out of state.
# ==============================================================================

removed {
  from = oci_identity_domains_app.k8s_exchange

  lifecycle {
    destroy = false
  }
}

removed {
  from = terraform_data.k8s_exchange_client_secret_version

  lifecycle {
    destroy = false
  }
}

removed {
  from = time_static.k8s_exchange_client_secret_rotated_at

  lifecycle {
    destroy = false
  }
}
