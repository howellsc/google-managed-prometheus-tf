resource "google_compute_network" "vpc" {
  name                    = "${var.name}-gmp-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet_gmp" {
  name          = "${var.name}-gmp"
  region        = var.region
  ip_cidr_range = "10.132.0.0/20"

  private_ip_google_access = true

  network = google_compute_network.vpc.id

  lifecycle {
    create_before_destroy = false
    replace_triggered_by  = [google_compute_network.vpc]
  }
}

resource "google_compute_subnetwork" "subnet_gke" {
  name = "${var.name}-subnet-gke"

  ip_cidr_range = "10.0.0.0/16"
  region        = var.region

  //  ipv6_access_type = "INTERNAL" # Change to "EXTERNAL" if creating an external loadbalancer

  network = google_compute_network.vpc.id
  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "192.168.0.0/24"
  }

  secondary_ip_range {
    range_name    = "pod-ranges"
    ip_cidr_range = "192.168.16.0/20"
  }
}
