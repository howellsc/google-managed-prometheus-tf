output "grafana_db_name" {
  value = google_sql_database_instance.grafana_db.name
}

output "grafana_db_password" {
  value = random_password.grafana_db_password.result
}

output "grafana_db_admin_password" {
  value = random_password.postgres_admin_password.result
}
