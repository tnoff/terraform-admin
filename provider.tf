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
      version = "~> 18.2"
    }
  }

  # Use local backend since we're creating the remote backend
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "oci" {
  region              = var.oci_region
  config_file_profile = var.config_file_profile
}

provider "gitlab" {
  token = var.gitlab_api_key
}
