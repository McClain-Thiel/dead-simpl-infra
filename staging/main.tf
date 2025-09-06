terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.staging_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.staging_cluster.master_auth[0].cluster_ca_certificate)
}

resource "google_container_cluster" "staging_cluster" {
  name               = "staging-cluster"
  location           = var.region
  initial_node_count = 1

  node_config {
    machine_type = "e2-medium"
    disk_type    = "pd-standard"
    disk_size_gb = 30
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

resource "google_secret_manager_secret" "staging_secret" {
  secret_id = "staging-secret"

  replication {
    user_managed {
      replicas {
        location = "us-central1"
      }
    }
  }
}

# Create the firebase secret in Kubernetes
data "google_secret_manager_secret_version" "firebase_adminsdk" {
  secret = "dead-simpl-firebase-adminsdk"
}

resource "kubernetes_secret" "firebase_adminsdk" {
  metadata {
    name      = "dead-simpl-firebase-adminsdk"
    namespace = "staging"
  }

  data = {
    "service-account.json" = data.google_secret_manager_secret_version.firebase_adminsdk.secret_data
  }

  type = "Opaque"
}