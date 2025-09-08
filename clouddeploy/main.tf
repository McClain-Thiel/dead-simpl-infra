terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Cloud Deploy targets for staging and production
resource "google_clouddeploy_target" "staging" {
  project  = var.project_id
  location = var.region
  name     = "staging"

  gke {
    cluster = "projects/${var.project_id}/locations/${var.region}/clusters/staging-cluster"
  }
}

resource "google_clouddeploy_target" "prod" {
  project  = var.project_id
  location = var.region
  name     = "prod"

  gke {
    cluster = "projects/${var.project_id}/locations/${var.region}/clusters/prod-cluster"
  }
}

# Delivery pipeline connecting the targets
resource "google_clouddeploy_delivery_pipeline" "dead_simpl" {
  project  = var.project_id
  location = var.region
  name     = "dead-simpl"

  serial_pipeline {
    stages {
      target_id = google_clouddeploy_target.staging.name
    }
    stages {
      target_id = google_clouddeploy_target.prod.name
    }
  }
}
