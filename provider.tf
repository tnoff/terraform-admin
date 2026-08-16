terraform {
  required_version = "~> 1.9"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "~> 19.0"
    }
    # Captures last-rotated timestamps for layer-1 admin tfvars via the
    # terraform_data/time_static pair pattern. See rotation-tracking.tf
    # and docs/projects/secret-age-tracker.md.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }

  # Use local backend since we're creating the remote backend.
  # State lives outside the repo tree so it can't be committed or wiped
  # by `git clean`; it holds secrets (OCI keys, GitLab token material).
  backend "local" {
    path = "/home/tnorth/.local/state/terraform-admin/terraform.tfstate"
  }
}

provider "oci" {
  region              = var.oci_region
  config_file_profile = var.config_file_profile
}

provider "gitlab" {
  token = var.gitlab_api_key
}
