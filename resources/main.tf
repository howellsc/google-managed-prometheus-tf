locals {
  state_bucket_region = var.region
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

terraform {
  # backend "gcs" {
  #   bucket = "terraform-state"
  #   prefix = "terraform/tfstate"
  # }
  backend "local" {}
}

resource "google_storage_bucket" "external_state" {
  name                        = "${var.project_id}-${var.name}-terraform-state"
  location                    = local.state_bucket_region
  uniform_bucket_level_access = true
}

# module "cloud_sql" {
#   source                    = "./modules/cloud/sql"
#   name                      = var.name
#   region                    = var.region
#   vpc_name                  = module.vpc_network.vpc_name
#   private_vpc_connection_id = module.vpc_network.private_vpc_connection_id
# }

module "vpc_network" {
  source = "./modules/vpc"
  region = var.region
  name   = var.name
}

module "gke" {
  source                            = "./modules/gke"
  name                              = var.name
  region                            = var.region
  project_id                        = var.project_id
  vpc_name                          = module.vpc_network.vpc_name
  vpc_subnet_gke_name               = module.vpc_network.vpc_subnet_gke_name
  vpc_subnet_gke_secondary_ip_range = module.vpc_network.vpc_subnet_gke_secondary_ip_range
  git_prometheus_rules_username     = "howellsc"
  git_prometheus_rules_pat          = ""
  git_prometheus_rules_url          = "https://github.com/howellsc/prometheus-rules.git"
  git_prometheus_rules_ref          = "main"
  git_prometheus_config_username    = "howellsc"
  git_prometheus_config_pat         = ""
  git_prometheus_config_url         = "https://github.com/howellsc/prometheus-config.git"
  git_prometheus_config_ref         = "main"

  # grafana_db_name                   = module.cloud_sql.grafana_db_name
  # grafana_db_password               = module.cloud_sql.grafana_db_password
  # grafana_db_admin_password         = module.cloud_sql.grafana_db_admin_password
}
