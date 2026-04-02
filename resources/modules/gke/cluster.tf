resource "google_container_cluster" "default" {
  name = "${var.name}-cluster"

  location = var.region

  initial_node_count       = 1
  enable_l4_ilb_subsetting = true

  network    = var.vpc_name
  subnetwork = var.vpc_subnet_gke_name

  private_cluster_config {
    enable_private_nodes = true
  }

  ip_allocation_policy {
    stack_type                    = "IPV4"
    services_secondary_range_name = var.vpc_subnet_gke_secondary_ip_range[0].range_name
    cluster_secondary_range_name  = var.vpc_subnet_gke_secondary_ip_range[1].range_name
  }

  # Set `deletion_protection` to `true` will ensure that one cannot
  # accidentally delete this instance by use of Terraform.
  deletion_protection = false
}
