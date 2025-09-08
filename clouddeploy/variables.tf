variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "region" {
  description = "The GCP region for Cloud Deploy resources."
  type        = string
  default     = "us-central1"
}
