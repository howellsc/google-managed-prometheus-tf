output "vpc_name" {
  value = google_compute_network.vpc.id
}

output "vpc_subnet_name" {
  value = google_compute_subnetwork.subnet_gmp.id
}

output "vpc_subnet_gke_name" {
  value = google_compute_subnetwork.subnet_gke.id
}

output "vpc_subnet_gke_secondary_ip_range" {
  value = google_compute_subnetwork.subnet_gke.secondary_ip_range
}
