output "ip_address" {
  value = google_compute_global_address.lb_ip.address
}

output "url" {
  value = "http://${google_compute_global_address.lb_ip.address}"
}