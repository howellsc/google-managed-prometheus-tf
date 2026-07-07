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
    "serviceAccount:${var.project_id}.svc.id.goog[${kubernetes_namespace_v1.observability_namespace.metadata[0].name}/${var.name}-otel-collector-ksa]"
  ]
}

# -- GMP Datasource Sync --
resource "google_service_account" "gmp_datasource_syncer_gsa" {
  account_id   = "${var.name}-gmp-datasource-syncer-sa"
  display_name = "GSA for GMP Datasource Syncher"
}

resource "google_project_iam_member" "gmp_datasource_syncer_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gmp_datasource_syncer_gsa.email}"
}

resource "google_project_iam_member" "gmp_datasource_syncer_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${google_service_account.gmp_datasource_syncer_gsa.email}"
}

resource "google_service_account_iam_binding" "gmp_datasource_syncer_wi_binding" {
  service_account_id = google_service_account.gmp_datasource_syncer_gsa.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${kubernetes_namespace_v1.observability_namespace.metadata[0].name}/${var.name}-gmp-datasource-syncer-ksa]"
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
    "serviceAccount:${var.project_id}.svc.id.goog[${kubernetes_namespace_v1.observability_namespace.metadata[0].name}/${var.name}-grafana-ksa]"
  ]
}

resource "google_service_account" "rule_evaluator_gsa" {
  account_id   = "${var.name}-gmp-rule-evaluator-sa"
  display_name = "GSA for GMP Rule Evaluator"
}

# 1. IAM Binding to allow your cluster's Service Account to read GMP data
resource "google_project_iam_member" "rule_evaluator_metric_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.rule_evaluator_gsa.email}"
}

# 1. IAM Binding to allow your cluster's Service Account to read GMP data
resource "google_project_iam_member" "rule_evaluator_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.rule_evaluator_gsa.email}"
}

resource "google_service_account_iam_binding" "rule_evaluator_wi_binding" {
  service_account_id = google_service_account.rule_evaluator_gsa.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${kubernetes_namespace_v1.observability_namespace.metadata[0].name}/${var.name}-gmp-rule-evaluator-ksa]"
  ]
}
