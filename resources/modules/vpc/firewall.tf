resource "google_compute_firewall" "allow_lb" {
  name    = "${var.name}-allow-lb"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16"
  ]
}