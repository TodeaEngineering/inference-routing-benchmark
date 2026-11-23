terraform {
  required_version = ">= 1.1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.30.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
}

provider "helm" {
  kubernetes = {
    host                   = "https://${module.cluster.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = module.cluster.ca_certificate
  }
}

data "google_client_config" "default" {}
