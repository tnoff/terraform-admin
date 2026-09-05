terraform {
  required_version = "~> 1.9"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.0"
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
    # Writes this repo's CI credentials to tnoff/terraform as GitHub Actions
    # secrets, the GitHub half of what `gitlab_project_variable` does below.
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
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

# Authenticates as the tnoff-terraform App, the same identity terraform/infra
# uses. This was the last consumer of the human admin PAT; with it gone the
# token can be revoked on github.com.
#
# Switched only after infra proved the App equivalent -- its plan reported "No
# changes" across all 23 repositories, which is the assertion that the App has
# exactly the access the PAT had rather than merely enough to look healthy.
#
# owner stays explicit for the same reason it did with the PAT: an installation
# token is scoped, but the provider still needs to know which account these
# resource addresses refer to.
provider "github" {
  owner = "tnoff"

  app_auth {
    id              = var.terraform_app_id
    installation_id = var.terraform_app_installation_id
    pem_file        = base64decode(var.terraform_app_private_key_b64)
  }
}
