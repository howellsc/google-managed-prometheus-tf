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

# resource "google_storage_bucket" "external_state" {
#   name                        = "${var.project_id}-${var.name}-terraform-state"
#   location                    = local.state_bucket_region
#   uniform_bucket_level_access = true
# }

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
}

# module "stateful_mig" {
#   source = "./modules/stateful-mig"
#
#   name              = var.name
#   zone              = var.zone
#   region            = var.region
#   subnetwork        = module.vpc_network.vpc_subnet_name
#   instance_template = google_compute_instance_template.default.id
#
#   instances = {
#     "node-1" = "10.132.0.10"
#     "node-2" = "10.132.0.11"
#   }
# }

# module "lb" {
#   source = "./modules/http-lb"
#
#   name                   = var.name
#   backend_instance_group = module.stateful_mig.instance_group
#   port                   = 80
# }

# resource "google_compute_instance_template" "default" {
#   name_prefix  = "my-template-"
#   machine_type = "e2-medium"
#
#   disk {
#     boot         = true
#     auto_delete  = true
#     source_image = "debian-cloud/debian-11"
#   }
#
#   network_interface {
#     subnetwork = module.vpc_network.vpc_subnet_name
#   }
#
#   tags = ["http-server"]
#
#   metadata_startup_script = <<-EOT
#     #!/bin/bash
#     apt-get update
#     apt-get install -y nginx
#     systemctl start nginx
#   EOT
# }
