# ==============================================================================
# 7. CLOUD SQL POSTGRES HA (Grafana Backend)
# ==============================================================================
resource "google_sql_database_instance" "grafana_db" {
  name             = "${var.name}-grafana-ha-postgres"
  database_version = "POSTGRES_15"
  region           = var.region

  # Ensure VPC peering completes before creating the DB
  depends_on = [var.private_vpc_connection_id]

  settings {
    tier              = "db-custom-2-7680" # 2 vCPU, 7.5GB RAM
    availability_type = "REGIONAL"         # <--- Makes the DB High Availability (HA)

    ip_configuration {
      ipv4_enabled                                  = false # Disable public IP
      private_network                               = var.vpc_name
      enable_private_path_for_google_cloud_services = true
    }
  }
}

resource "google_sql_database" "grafana" {
  name     = "${var.name}-grafana"
  instance = google_sql_database_instance.grafana_db.name
}

resource "random_password" "grafana_db_password" {
  length  = 16
  special = false
}

resource "google_sql_user" "grafana_user" {
  name     = "grafana"
  instance = google_sql_database_instance.grafana_db.name
  password = random_password.grafana_db_password.result
}

resource "random_password" "postgres_admin_password" {
  length  = 16
  special = false
}

resource "google_sql_user" "postgres_admin" {
  name     = "postgres"
  instance = google_sql_database_instance.grafana_db.name
  password = random_password.postgres_admin_password.result
}