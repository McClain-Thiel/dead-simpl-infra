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
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "servicenetworking" {
  project = var.project_id
  service = "servicenetworking.googleapis.com"
}

resource "google_project_service" "sqladmin" {
  project = var.project_id
  service = "sqladmin.googleapis.com"
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.staging_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.staging_cluster.master_auth[0].cluster_ca_certificate)
}

# Get existing cluster info for IP restrictions  
data "google_container_cluster" "staging_cluster_info" {
  name     = "staging-cluster"
  location = var.region
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

# Reserve static external IPs for LoadBalancer services
resource "google_compute_global_address" "frontend_staging_ip" {
  name = "frontend-staging-ip"
}

resource "google_compute_global_address" "backend_staging_ip" {
  name = "backend-staging-ip"
}

# Enable private services access for CloudSQL
resource "google_compute_global_address" "private_ip_alloc" {
  name          = "private-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
}

# CloudSQL Postgres instance for staging
resource "google_sql_database_instance" "staging_postgres" {
  name             = "staging-postgres"
  database_version = "POSTGRES_15"
  region           = var.region
  deletion_protection = false

  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier = "db-f1-micro"
    
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
    }
    
    backup_configuration {
      enabled = true
      start_time = "03:00"
    }
  }
}


# Database and user
resource "google_sql_database" "staging_db" {
  name     = "staging_db"
  instance = google_sql_database_instance.staging_postgres.name
}

resource "google_sql_user" "staging_user" {
  name     = "staging_user"
  instance = google_sql_database_instance.staging_postgres.name
  password = random_password.db_password.result
}

resource "random_password" "db_password" {
  length  = 16
  special = true
}

# Store database credentials in Secret Manager
resource "google_secret_manager_secret" "staging_db_url" {
  secret_id = "staging-db-url"

  replication {
    user_managed {
      replicas {
        location = "us-central1"
      }
    }
  }
}

resource "google_secret_manager_secret_version" "staging_db_url" {
  secret = google_secret_manager_secret.staging_db_url.id
  secret_data = "postgresql://${google_sql_user.staging_user.name}:${random_password.db_password.result}@${google_sql_database_instance.staging_postgres.private_ip_address}/${google_sql_database.staging_db.name}"
}

# Create database URL secret in Kubernetes
data "google_secret_manager_secret_version" "staging_db_url" {
  secret = google_secret_manager_secret.staging_db_url.secret_id
  depends_on = [google_secret_manager_secret_version.staging_db_url]
}

resource "kubernetes_secret" "staging_db_url" {
  metadata {
    name      = "staging-db-url"
    namespace = "staging"
  }

  data = {
    "SUPABASE_DB_STRING" = data.google_secret_manager_secret_version.staging_db_url.secret_data
  }

  type = "Opaque"
}