resource "google_container_cluster" "default" {
  name = "${var.name}-cluster"

  location = var.region

  enable_l4_ilb_subsetting = true

  network    = var.vpc_name
  subnetwork = var.vpc_subnet_gke_name

  # 2. Define the node pool INSIDE the cluster resource
  node_pool {
    name       = "${var.name}-default-pool"
    node_count = 1 # Number of nodes per zone

    node_config {
      machine_type = "e2-standard-2"

      # Tell the nodes to pass Workload Identity to your K8s Pods
      workload_metadata_config {
        mode = "GKE_METADATA"
      }

      # # Grant the underlying VMs the scope to talk to GCP APIs
      # oauth_scopes = [
      #   "https://www.googleapis.com/auth/cloud-platform"
      # ]
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

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
