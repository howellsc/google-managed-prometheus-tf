# 1. Karma ConfigMap
resource "kubernetes_config_map_v1" "karma_config" {
  metadata {
    name      = "${var.name}-karma-config"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }

  data = {
    "karma.conf" = <<EOF
alertmanager:
  interval: 30s
  servers:
    - name: primary
      uri: http://${var.name}-alertmanager.${var.name}-observability.svc.cluster.local:9093
      proxy: true
      timeout: 10s
      healthcheck:
        filters:
          prometheus:
            - alertname=DeadMansSwitch
labels:
  strip:
    - prometheus
history:
  rewrite:
    - source: '(.*)'
      uri: 'http://127.0.0.1:9090'
EOF
  }
}

# 2. Karma Deployment
resource "kubernetes_deployment_v1" "karma" {
  metadata {
    name      = "${var.name}-karma"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = "${var.name}-karma"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "${var.name}-karma"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "${var.name}-karma"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.grafana_ksa.metadata[0].name
        container {
          name  = "${var.name}-karma"
          image = "lmierzwa/karma"

          port {
            name           = "http"
            container_port = 8080
          }

          env {
            name  = "CONFIG_FILE"
            value = "/etc/karma/karma.conf"
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/karma"
            read_only  = true
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        container {
          name  = "${var.name}-frontend"
          image = "gke.gcr.io/prometheus-engine/frontend:v0.17.4-gke.1"

          args = [
            "--web.listen-address=:9090",
            "--query.project-id=${var.project_id}"
          ]

          port {
            name           = "web"
            container_port = 9090
          }

          readiness_probe {
            http_get {
              path = "/-/ready"
              port = 9090
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/-/healthy"
              port = 9090
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }

          resources {
            limits = {
              cpu    = "250m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.karma_config.metadata[0].name
          }
        }
      }
    }
  }
}

# 3. Karma Service
resource "kubernetes_service_v1" "karma" {
  metadata {
    name      = "${var.name}-karma"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
    labels = {
      "app.kubernetes.io/name" = "${var.name}-karma"
    }
  }

  spec {
    type = "ClusterIP"

    port {
      name        = "http"
      port        = 8080
      target_port = "http"
    }

    selector = {
      "app.kubernetes.io/name" = "${var.name}-karma"
    }
  }
}
