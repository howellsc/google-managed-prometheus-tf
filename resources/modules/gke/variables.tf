variable "name" {
  description = "The unique name for the resource set"
  type        = string
}

variable "project_id" {
  description = "The GCP Project Id"
  type        = string
}

variable "vpc_name" {
  description = "VPC Name"
  type        = string
}

variable "vpc_subnet_gke_name" {
  description = "VPC GKE subnet name"
  type        = string
}

variable "vpc_subnet_gke_secondary_ip_range" {
  description = "VPC GKE subnet secondary ip range"
  type = list(object({
    range_name    = string
    ip_cidr_range = string
  }))
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
}

variable "grafana_db_name" {
  description = "Grafana Postgres DB Name"
  type        = string
}

variable "grafana_db_password" {
  description = "Grafana Postgres DB Password"
  type        = string
}

variable "grafana_db_admin_password" {
  description = "Grafana Postgres DB Admin Password"
  type        = string
}