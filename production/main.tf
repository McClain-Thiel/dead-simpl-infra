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
  host                   = "https://${google_container_cluster.prod_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.prod_cluster.master_auth[0].cluster_ca_certificate)
}

resource "google_container_cluster" "prod_cluster" {
  name               = "prod-cluster"
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

provider "helm" {
  kubernetes = {
    host                   = "https://${google_container_cluster.prod_cluster.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.prod_cluster.master_auth[0].cluster_ca_certificate)
  }
}

resource "google_secret_manager_secret" "prod_secret" {
  secret_id = "prod-secret"

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
    namespace = "production"
  }

  data = {
    "service-account.json" = data.google_secret_manager_secret_version.firebase_adminsdk.secret_data
  }

  type = "Opaque"
}

# Reserve static external IPs for LoadBalancer services
resource "google_compute_global_address" "frontend_prod_ip" {
  name = "frontend-prod-ip"
}

resource "google_compute_global_address" "backend_prod_ip" {
  name = "backend-prod-ip"
}

resource "helm_release" "backend_prod" {
  name             = "backend-prod"
  chart            = "/Users/mcclainthiel/Documents/dead-simpl/helm/backend"
  namespace        = "production"
  create_namespace = true

  values = [
    file("/Users/mcclainthiel/Documents/dead-simpl/helm/backend/values.prod.yaml")
  ]
}

resource "helm_release" "frontend_prod" {
  name             = "frontend-prod"
  chart            = "/Users/mcclainthiel/Documents/dead-simpl/helm/frontend"
  namespace        = "production"
  create_namespace = true

  values = [
    file("/Users/mcclainthiel/Documents/dead-simpl/helm/frontend/values.prod.yaml")
  ]
}