resource "kubernetes_service_account_v1" "gmp_datasource_syncer_ksa" {
  metadata {
    name      = "${var.name}-gmp-datasource-syncer-ksa"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.gmp_datasource_syncer_gsa.email
    }
  }
}

resource "kubernetes_service_account_v1" "grafana_ksa" {
  metadata {
    name      = "${var.name}-grafana-ksa"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.grafana_gsa.email
    }
  }
}

resource "kubernetes_cron_job_v1" "prometheus_gmp_datasource_syncer" {
  metadata {
    name      = "${var.name}-gmp-datasource-syncer"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }

  spec {

    schedule = "*/15 * * * *"

    successful_jobs_history_limit = 3
    failed_jobs_history_limit = 1

    concurrency_policy = "Forbid"

    job_template {

      metadata {
        labels = {
          app = "${var.name}-gmp-datasource-syncer"
        }
      }

      spec {

        template {

          metadata {
            labels = {
              app = "${var.name}-gmp-datasource-syncer"
            }
          }

          spec {

            service_account_name = kubernetes_service_account_v1.gmp_datasource_syncer_ksa.metadata[0].name

            container {
              image = "gke.gcr.io/prometheus-engine/datasource-syncer:v0.18.1-gke.0"
              name  = "${var.name}-gmp-datasource-syncer"

              args = [
                "--grafana-api-endpoint=http://${var.name}-grafana-service",
                "--project-id=${var.project_id}",
                "--datasource-uids=",
                "--grafana-api-token="
              ]

              security_context {
                allow_privilege_escalation = false
                capabilities {
                  drop = ["ALL"]
                }
                run_as_non_root           = false
                read_only_root_filesystem = true
                run_as_user               = "1000"
              }
            }

            toleration {
              effect   = "NoSchedule"
              key      = "kubernetes.io/arch"
              operator = "Equal"
              value    = "amd64"
            }
          }
        }
      }
    }

  }
}

resource "kubernetes_deployment_v1" "grafana" {
  metadata {
    name      = "${var.name}-grafana"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }
  spec {
    replicas = 1 # <--- Grafana HA (2 pods) enabled because of external DB!
    selector {
      match_labels = {
        app = "${var.name}-grafana"
      }
    }
    template {
      metadata {
        labels = {
          app = "${var.name}-grafana"
        }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.grafana_ksa.metadata[0].name

        # Container 1: The Grafana Application
        container {
          name  = "${var.name}-grafana"
          image = "grafana/grafana:latest"
          port {
            container_port = 3000
          }
          # Point Grafana to the localhost proxy
          # env {
          #   name  = "GF_DATABASE_TYPE"
          #   value = "postgres"
          # }
          # env {
          #   name  = "GF_DATABASE_HOST"
          #   value = "127.0.0.1:5432"
          # }
          # env {
          #   name  = "GF_DATABASE_NAME"
          #   value = "grafana"
          # }
          # env {
          #   name  = "GF_DATABASE_USER"
          #   value = "grafana"
          # }
          # env {
          #   name = "GF_DATABASE_PASSWORD"
          #   value_from {
          #     secret_key_ref {
          #       name = kubernetes_secret_v1.grafana_db_credentials.metadata[0].name
          #       key  = "password"
          #     }
          #   }
          # }
        }

        # # Container 2: Cloud SQL Auth Proxy Sidecar
        # container {
        #   name  = "cloud-sql-proxy"
        #   image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.0"
        #   # Run proxy to connect to our specific DB over Private IP
        #   args = [
        #     "--private-ip",
        #     "${var.project_id}:${var.region}:${var.grafana_db_name}"
        #   ]
        #   security_context {
        #     run_as_non_root = true
        #   }
        # }

        container {
          name = "${var.name}-grafana-otel-collector"
          # Contrib image is required as it contains the googlemanagedprometheus exporter
          image = "otel/opentelemetry-collector-contrib:latest"
          args  = ["--config=/etc/otelcol-contrib/config.yaml"]

          volume_mount {
            name       = "grafana-otel-collector-config-volume"
            mount_path = "/etc/otelcol-contrib"
          }
        }

        volume {
          name = "grafana-otel-collector-config-volume"
          config_map {
            name = kubernetes_config_map_v1.grafana_otel_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "grafana_service" {
  metadata {
    name      = "${var.name}-grafana-service"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }
  spec {
    selector = {
      app = "${var.name}-grafana"
    }
    port {
      port        = 80
      target_port = 3000
    }
    type = "ClusterIP"
  }

  depends_on = [time_sleep.wait_service_cleanup]
}

resource "kubernetes_config_map_v1" "grafana_otel_config" {
  metadata {
    name      = "${var.name}-grafana-otel-collector-config"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }
  data = {
    "config.yaml" = <<EOF
receivers:
  prometheus:
    config:
      scrape_configs:
        - job_name: otelcol
          scrape_interval: 30s
          static_configs:
            - targets: ["127.0.0.1:8888"]
        - job_name: grafana
          scrape_interval: 30s
          metrics_path: /metrics
          static_configs:
            - targets: ["127.0.0.1:3000"]
processors:
  batch:
    send_batch_size: 200
    timeout: 5s
  resourcedetection:
    detectors: [gcp,env]
    timeout: 2s
    override: false
exporters:
  googlemanagedprometheus:
    project: "${var.project_id}"
service:

  telemetry:
    metrics:
      readers:
        - pull:
            exporter:
              prometheus:
                host: '127.0.0.1'
                port: 8888

  pipelines:
    metrics:
      receivers: [prometheus]
      processors: [resourcedetection, batch]
      exporters: [googlemanagedprometheus]
EOF
  }
}

# Store the generated DB password securely in K8s
# resource "kubernetes_secret_v1" "grafana_db_credentials" {
#   metadata {
#     name      = "${var.name}-grafana-db-credentials"
#     namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
#   }
#   data = {
#     password = var.grafana_db_password
#   }
# }

# 2. Store the admin password in K8s Secret
# resource "kubernetes_secret_v1" "postgres_admin_credentials" {
#   metadata {
#     name      = "${var.name}-postgres-admin-credentials"
#     namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
#   }
#   data = {
#     password = var.grafana_db_admin_password
#   }
# }

# # 3. Deploy a one-time Kubernetes Job to run the internal SQL Grants
# resource "kubernetes_job_v1" "grafana_db_permissions" {
#   metadata {
#     name      = "${var.name}-grafana-db-permissions"
#     namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
#   }
#   spec {
#     template {
#       metadata {
#         labels = {
#           app = "${var.name}-grafana-db-permissions"
#         }
#       }
#       spec {
#         restart_policy = "Never"
#
#         # We reuse the Grafana KSA because it already has Workload Identity
#         # and the "roles/cloudsql.client" IAM role needed by the proxy.
#         service_account_name = kubernetes_service_account_v1.grafana_ksa.metadata[0].name
#
#         container {
#           name = "psql-proxy-runner"
#           # Use the Postgres Alpine image so we have access to both 'psql' and 'wget'
#           image = "postgres:15-alpine"
#
#           env {
#             name = "POSTGRES_PASSWORD"
#             value_from {
#               secret_key_ref {
#                 name = kubernetes_secret_v1.postgres_admin_credentials.metadata[0].name
#                 key  = "password"
#               }
#             }
#           }
#
#           command = ["/bin/sh", "-c"]
#
#           # Single-container execution script: runs the proxy in the background,
#           # executes the grants, and kills the proxy so the K8s Job completes successfully.
#           args = [
#             <<-EOT
#             echo "Downloading Cloud SQL Proxy..."
#             wget -q https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.11.0/cloud-sql-proxy.linux.amd64 -O cloud-sql-proxy
#             chmod +x cloud-sql-proxy
#
#             echo "Starting Cloud SQL Proxy in the background..."
#             ./cloud-sql-proxy --private-ip ${var.project_id}:${var.region}:${var.grafana_db_name} &
#             PROXY_PID=$!
#
#             echo "Waiting 10 seconds for proxy tunnel to establish..."
#             sleep 10
#
#             echo "Executing internal PostgreSQL permission grants..."
#             PGPASSWORD=$POSTGRES_PASSWORD psql -h 127.0.0.1 -U postgres -d grafana -c "
#             ALTER DATABASE grafana OWNER TO grafana;
#             GRANT CREATE ON DATABASE grafana TO grafana;
#             GRANT ALL ON SCHEMA public TO grafana;
#             "
#
#             echo "Grants applied successfully. Terminating proxy..."
#             kill $PROXY_PID
#             EOT
#           ]
#         }
#       }
#     }
#   }
#
#   # # Ensure the Job only runs AFTER the database and users actually exist
#   # depends_on =[
#   #   google_sql_database.grafana,
#   #   var.,
#   #   google_sql_user.postgres_admin
#   # ]
# }