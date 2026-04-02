# -- OTel Collector (Metric Writer) --
resource "google_service_account" "otel_gsa" {
  account_id   = "otel-gcp-sa"
  display_name = "GSA for OTel Collector pushing to GMP"
}

resource "google_project_iam_member" "otel_gsa_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.otel_gsa.email}"
}

resource "google_service_account_iam_binding" "otel_wi_binding" {
  service_account_id = google_service_account.otel_gsa.name
  role               = "roles/iam.workloadIdentityUser"
  members =[
    "serviceAccount:${var.project_id}.svc.id.goog[monitoring/otel-collector-ksa]"
  ]
}

# -- Prometheus UI Proxy (Metric Viewer) --
resource "google_service_account" "prom_ui_gsa" {
  account_id   = "prom-ui-gcp-sa"
  display_name = "GSA for Prom UI reading from GMP"
}

resource "google_project_iam_member" "prom_ui_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.prom_ui_gsa.email}"
}

resource "google_service_account_iam_binding" "prom_ui_wi_binding" {
  service_account_id = google_service_account.prom_ui_gsa.name
  role               = "roles/iam.workloadIdentityUser"
  members =[
    "serviceAccount:${var.project_id}.svc.id.goog[monitoring/prom-ui-ksa]"
  ]
}