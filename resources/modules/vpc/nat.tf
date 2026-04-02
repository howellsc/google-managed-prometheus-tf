# Cloud Router
resource "google_compute_router" "nat_router" {
  name    = "${var.name}-nat-router"
  region  = var.region
  network = google_compute_network.vpc.name
}

# Cloud NAT
resource "google_compute_router_nat" "cloud_nat" {
  name                               = "${var.name}-cloud-nat"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
