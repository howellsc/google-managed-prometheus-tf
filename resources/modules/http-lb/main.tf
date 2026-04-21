# Static external IP
resource "google_compute_global_address" "lb_ip" {
  name = "${var.name}-ip"
}

# Health check
resource "google_compute_health_check" "http" {
  name = "${var.name}-hc"

  http_health_check {
    port         = var.port
    request_path = var.health_check_path
  }
}

# Backend service
resource "google_compute_backend_service" "default" {
  name                  = "${var.name}-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 10
  port_name             = "http"

  health_checks = [google_compute_health_check.http.id]

  backend {
    group = var.backend_instance_group
  }
}

# URL map
resource "google_compute_url_map" "default" {
  name            = "${var.name}-url-map"
  default_service = google_compute_backend_service.default.id
}

# HTTP proxy
resource "google_compute_target_http_proxy" "default" {
  name    = "${var.name}-proxy"
  url_map = google_compute_url_map.default.id
}

# Forwarding rule
resource "google_compute_global_forwarding_rule" "http" {
  name       = "${var.name}-fw"
  target     = google_compute_target_http_proxy.default.id
  port_range = "80"
  ip_address = google_compute_global_address.lb_ip.address
}