# -- OTel Collector (Metric Writer) --
resource "google_service_account" "otel_gsa" {
  account_id   = "${var.name}-otel-gcp-sa"
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
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${kubernetes_namespace_v1.observability_namespace.metadata[0].name}/otel-collector-ksa]"
  ]
}

# -- Prometheus UI Proxy (Metric Viewer) --
resource "google_service_account" "prom_ui_gsa" {
  account_id   = "${var.name}-prom-ui-gcp-sa"
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
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${kubernetes_namespace_v1.observability_namespace.metadata[0].name}/prom-ui-ksa]"
  ]
}

resource "google_service_account" "grafana_gsa" {
  account_id   = "${var.name}-grafana-gcp-sa"
  display_name = "GSA for Grafana (Cloud SQL & GMP Access)"
}

# Grant access to Cloud SQL (for the sidecar proxy)
resource "google_project_iam_member" "grafana_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.grafana_gsa.email}"
}

# Grant access to Google Managed Prometheus (so Grafana can query your metrics)
resource "google_project_iam_member" "grafana_metric_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.grafana_gsa.email}"
}

resource "google_service_account_iam_binding" "grafana_wi_binding" {
  service_account_id = google_service_account.grafana_gsa.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${kubernetes_namespace_v1.observability_namespace.metadata[0].name}/grafana-ksa]"
  ]
}
