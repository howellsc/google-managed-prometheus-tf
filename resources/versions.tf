terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.26.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27" # <--- Bump this to a newer version
    }
  }
}