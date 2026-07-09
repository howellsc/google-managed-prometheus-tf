resource "kubernetes_service_account_v1" "otel_ksa" {
  metadata {
    name      = "${var.name}-otel-collector-ksa"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.otel_gsa.email
    }
  }
}

# -- OTel Collector Deployment & Config --
resource "kubernetes_config_map_v1" "otel_config" {
  metadata {
    name      = "${var.name}-otel-collector-config"
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
  prometheus:
    config:
      scrape_configs:
        - job_name: otelcol
          scrape_interval: 30s
          static_configs:
            - targets: ["127.0.0.1:8888"]
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
      receivers: [otlp, prometheus]
      processors: [resourcedetection, batch]
      exporters: [googlemanagedprometheus]
EOF
  }
}

resource "kubernetes_deployment_v1" "otel_collector" {
  metadata {
    name      = "${var.name}-otel-collector"
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