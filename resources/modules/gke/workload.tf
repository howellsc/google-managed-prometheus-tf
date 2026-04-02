data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.default.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.default.master_auth[0].cluster_ca_certificate)

  ignore_annotations = [
    "^autopilot\\.gke\\.io\\/.*",
    "^cloud\\.google\\.com\\/.*"
  ]
}

resource "kubernetes_namespace_v1" "observability_namespace" {
  metadata {
    name = "${var.name}-namespace"
  }
}

# -- Kubernetes Service Accounts (KSAs) --
resource "kubernetes_service_account_v1" "otel_ksa" {
  metadata {
    name      = "otel-collector-ksa"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.otel_gsa.email
    }
  }
}

resource "kubernetes_service_account_v1" "prom_ui_ksa" {
  metadata {
    name      = "prom-ui-ksa"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.prom_ui_gsa.email
    }
  }
}

# -- OTel Collector Deployment & Config --
resource "kubernetes_config_map_v1" "otel_config" {
  metadata {
    name      = "otel-collector-config"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }
  data = {
    "config.yaml" = <<EOF
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
processors:
  batch:
    send_batch_size: 200
    timeout: 5s
  resourcedetection:
    detectors: [env, gcp]
    timeout: 2s
    override: false
exporters:
  googlemanagedprometheus:
    project: "${var.project_id}"
service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [resourcedetection, batch]
      exporters: [googlemanagedprometheus]
EOF
  }
}

resource "kubernetes_deployment_v1" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "otel-collector"
      }
    }
    template {
      metadata {
        labels = {
          app = "otel-collector"
        }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.otel_ksa.metadata[0].name
        container {
          name = "otel-collector"
          # Contrib image is required as it contains the googlemanagedprometheus exporter
          image = "otel/opentelemetry-collector-contrib:latest"
          args  = ["--config=/etc/otelcol-contrib/config.yaml"]
          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/otelcol-contrib"
          }
        }
        volume {
          name = "config-volume"
          config_map {
            name = kubernetes_config_map_v1.otel_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "prometheus_ui_deployment" {
  metadata {
    name      = "app-prometheus-ui"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }

  spec {
    selector {
      match_labels = {
        app = "app-prometheus-ui"
      }
    }

    template {
      metadata {
        labels = {
          app = "app-prometheus-ui"
        }
      }

      spec {
        container {
          image = "gke.gcr.io/prometheus-engine/frontend:v0.15.3-gke.0"
          name  = "frontend"

          args = ["--query.project-id=${var.project_id}"]
          port {
            container_port = 9090
            name           = "web"
          }

          security_context {
            allow_privilege_escalation = false
            privileged                 = false
            read_only_root_filesystem  = false
          }

          liveness_probe {
            http_get {
              path = "/"
              port = "gmp-svc"
            }

            initial_delay_seconds = 3
            period_seconds        = 3
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

resource "kubernetes_service_v1" "prom_ui_service" {
  metadata {
    name      = "prometheus-ui-service"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
    annotations = {
      "networking.gke.io/load-balancer-type" = "Internal" # Remove to create an external loadbalancer
    }
  }
  spec {
    type = "LoadBalancer"
    selector = {
      app = kubernetes_deployment_v1.prometheus_ui_deployment.spec[0].selector[0].match_labels.app
    }
    port {
      port        = 9090
      target_port = kubernetes_deployment_v1.prometheus_ui_deployment.spec[0].template[0].spec[0].container[0].port[0].name
    }
  }

  depends_on = [time_sleep.wait_service_cleanup]

}

resource "kubernetes_service_account" "grafana_ksa" {
  metadata {
    name      = "grafana-ksa"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.grafana_gsa.email
    }
  }
}

resource "kubernetes_deployment_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }
  spec {
    replicas = 2 # <--- Grafana HA (2 pods) enabled because of external DB!
    selector {
      match_labels = {
        app = "grafana"
      }
    }
    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }
      spec {
        service_account_name = kubernetes_service_account.grafana_ksa.metadata[0].name

        # Container 1: The Grafana Application
        container {
          name  = "grafana"
          image = "grafana/grafana:latest"
          port {
            container_port = 3000
          }
          # Point Grafana to the localhost proxy
          env {
            name  = "GF_DATABASE_TYPE"
            value = "postgres"
          }
          env {
            name  = "GF_DATABASE_HOST"
            value = "127.0.0.1:5432"
          }
          env {
            name  = "GF_DATABASE_NAME"
            value = "grafana"
          }
          env {
            name  = "GF_DATABASE_USER"
            value = "grafana"
          }
          env {
            name = "GF_DATABASE_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.grafana_db_credentials.metadata[0].name
                key  = "password"
              }
            }
          }
        }

        # Container 2: Cloud SQL Auth Proxy Sidecar
        container {
          name  = "cloud-sql-proxy"
          image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.0"
          # Run proxy to connect to our specific DB over Private IP
          args = [
            "--private-ip",
            "${var.project_id}:${var.region}:${var.grafana_db_name}"
          ]
          security_context {
            run_as_non_root = true
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "grafana_service" {
  metadata {
    name      = "grafana-service"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }
  spec {
    selector = {
      app = "grafana"
    }
    port {
      port        = 80
      target_port = 3000
    }
    type = "ClusterIP"
  }

  depends_on = [time_sleep.wait_service_cleanup]
}

# Store the generated DB password securely in K8s
resource "kubernetes_secret_v1" "grafana_db_credentials" {
  metadata {
    name      = "grafana-db-credentials"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }
  data = {
    password = var.grafana_db_password
  }
}

# Provide time for Service cleanup
resource "time_sleep" "wait_service_cleanup" {
  depends_on = [google_container_cluster.default]

  destroy_duration = "180s"
}
