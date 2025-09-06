variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "region" {
  description = "The GCP region for the resources."
  type        = string
  default     = "us-central1"
}

variable "github_owner" {
  description = "The owner of the GitHub repository."
  type        = string
}

variable "backend_repo_name" {
  description = "The name of the backend GitHub repository."
  type        = string
}

variable "frontend_repo_name" {
  description = "The name of the frontend GitHub repository."
  type        = string
}