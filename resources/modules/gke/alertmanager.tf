locals {
  alertmanager_web_port       = 9093
  alertmanager_mesh_port      = 9094
  gmp_rule_evaluator_web_port = 9091
}


resource "kubernetes_service_account_v1" "gmp_rule_evaluator_ksa" {
  metadata {
    name      = "${var.name}-gmp-rule-evaluator-ksa"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.rule_evaluator_gsa.email
    }
  }
}

# 3. Headless Service for StatefulSet Sticky Network Identity
resource "kubernetes_service_v1" "alertmanager_service" {
  metadata {
    name      = "${var.name}-alertmanager"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
    labels = {
      app = "${var.name}-alertmanager"
    }
  }

  spec {
    selector = {
      app = "${var.name}-alertmanager"
    }

    port {
      name        = "web"
      port        = local.alertmanager_web_port
      target_port = local.alertmanager_web_port
    }

    port {
      name        = "mesh"
      port        = local.alertmanager_mesh_port
      target_port = local.alertmanager_mesh_port
    }

    # "None" defines it as headless, creating direct DNS paths for each pod instance
    cluster_ip = "None"
  }
}

# 4. Alertmanager StatefulSet Deployment
resource "kubernetes_stateful_set_v1" "alertmanager" {
  metadata {
    name      = "${var.name}-alertmanager"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }

  spec {
    service_name = kubernetes_service_v1.alertmanager_service.metadata[0].name
    replicas     = 3

    selector {
      match_labels = {
        app = "${var.name}-alertmanager"
      }
    }

    template {
      metadata {
        labels = {
          app = "${var.name}-alertmanager"
        }
      }

      spec {

        service_account_name = kubernetes_service_account_v1.gmp_rule_evaluator_ksa.metadata[0].name

        container {
          name  = "${var.name}-alertmanager"
          image = "quay.io/prometheus/alertmanager:v0.27.0"

          args = [
            "--config.file=/etc/alertmanager/current/alertmanager.yml",
            "--storage.path=/alertmanager",
            # 2. Point to the headless service DNS pattern to find cluster siblings
            "--cluster.peer=${var.name}-alertmanager-0.${kubernetes_service_v1.alertmanager_service.metadata[0].name}.${kubernetes_namespace_v1.observability_namespace.metadata[0].name}.svc.cluster.local:${local.alertmanager_mesh_port}",
            "--cluster.peer=${var.name}-alertmanager-1.${kubernetes_service_v1.alertmanager_service.metadata[0].name}.${kubernetes_namespace_v1.observability_namespace.metadata[0].name}.svc.cluster.local:${local.alertmanager_mesh_port}",
            "--cluster.peer=${var.name}-alertmanager-2.${kubernetes_service_v1.alertmanager_service.metadata[0].name}.${kubernetes_namespace_v1.observability_namespace.metadata[0].name}.svc.cluster.local:${local.alertmanager_mesh_port}"
          ]

          port {
            name           = "web"
            container_port = local.alertmanager_web_port
          }

          port {
            name           = "mesh"
            container_port = local.alertmanager_mesh_port
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/alertmanager"
          }

          volume_mount {
            name       = "${var.name}-alertmanager-storage"
            mount_path = "/alertmanager"
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
          }
        }

        container {
          name  = "${var.name}-config-reloader"
          image = "gke.gcr.io/prometheus-engine/config-reloader:v0.17.2-gke.2"

          args = [
            "-watched-dir=/etc/alertmanager/current",
            "-reload-url=http://127.0.0.1:${local.alertmanager_web_port}/-/reload",
            "-ready-url=http://127.0.0.1:${local.alertmanager_web_port}/-/ready"
          ]

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/alertmanager"
          }
        }

        container {
          name  = "${var.name}-git-prometheus-config-sync"
          image = "registry.k8s.io/git-sync/git-sync:v4.2.4"
          args = [
            "--period=30s",
            "--repo=${var.git_alertmanager_config_url}",
            "--ref=${var.git_alertmanager_config_ref}",
            "--root=/git",
            "--link=current",
            "--one-time=false",
          ]
          env {
            name = "GITSYNC_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.gmp_git_alertmanager_config_sync_secret.metadata[0].name
                key  = "username"
              }
            }
          }
          env {
            name = "GITSYNC_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.gmp_git_alertmanager_config_sync_secret.metadata[0].name
                key  = "token"
              }
            }
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/git"
          }
        }

        container {
          name = "${var.name}-alertmanager-otel-collector"
          # Contrib image is required as it contains the googlemanagedprometheus exporter
          image = "otel/opentelemetry-collector-contrib:latest"
          args  = ["--config=/etc/otelcol-contrib/config.yaml"]

          volume_mount {
            name       = "alertmanager-otel-collector-config-volume"
            mount_path = "/etc/otelcol-contrib"
          }

          env {
            name = "K8S_POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          env {
            name = "K8S_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }
        }

        volume {
          name = "config-volume"
          empty_dir {}
        }

        volume {
          name = "alertmanager-otel-collector-config-volume"
          config_map {
            name = kubernetes_config_map_v1.alertmanager_otel_config.metadata[0].name
          }
        }

        security_context {
          run_as_group    = "65534"
          run_as_user     = "65534"
          run_as_non_root = true
          fs_group        = "65534"
        }
      }


    }

    # Dynamically spins up dedicated persistent cloud disks per Pod replica
    volume_claim_template {
      metadata {
        name = "${var.name}-alertmanager-storage"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "standard-rwo" # Adjust to match your cloud's block storage class (e.g., premium-rwo)
        resources {
          requests = {
            storage = "1Gi"
          }
        }
      }
    }
  }
}

# 4. Standalone Rule Evaluator Deployment
resource "kubernetes_deployment_v1" "gmp_rule_evaluator" {
  metadata {
    name      = "${var.name}-gmp-rule-evaluator"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }

  spec {
    replicas = 1 # Must be exactly 1 to avoid duplicate evaluation/alert firing rings

    selector {
      match_labels = {
        app = "${var.name}-gmp-rule-evaluator"
      }
    }

    template {
      metadata {
        labels = {
          app = "${var.name}-gmp-rule-evaluator"
        }
      }

      spec {

        service_account_name = kubernetes_service_account_v1.gmp_rule_evaluator_ksa.metadata[0].name

        container {
          name  = "${var.name}-evaluator"
          image = "gke.gcr.io/prometheus-engine/rule-evaluator:v0.18.1-gke.0"

          args = [
            "--query.project-id=${var.project_id}",
            "--config.file=/etc/config/current/prometheus.yaml",
            "--log.level=debug"
          ]

          volume_mount {
            name       = "rules-volume"
            mount_path = "/etc/rules"
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/config"
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "20m"
              memory = "64Mi"
            }
          }
        }

        container {
          name  = "${var.name}-config-reloader"
          image = "gke.gcr.io/prometheus-engine/config-reloader:v0.17.2-gke.2"

          args = [
            "-watched-dir=/etc/rules/current",
            "-watched-dir=/etc/config/current",
            "-reload-url=http://127.0.0.1:${local.gmp_rule_evaluator_web_port}/-/reload",
            "-ready-url=http://127.0.0.1:${local.gmp_rule_evaluator_web_port}/-/ready"
          ]

          volume_mount {
            name       = "rules-volume"
            mount_path = "/etc/rules"
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/config"
          }
        }

        container {
          name  = "${var.name}-git-prometheus-rule-sync"
          image = "registry.k8s.io/git-sync/git-sync:v4.2.4"
          args = [
            "--period=30s",
            "--repo=${var.git_prometheus_rules_url}",
            "--ref=${var.git_prometheus_rules_ref}",
            "--root=/git",
            "--link=current",
            "--one-time=false",
          ]
          env {
            name = "GITSYNC_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.gmp_git_prometheus_rule_sync_secret.metadata[0].name
                key  = "username"
              }
            }
          }
          env {
            name = "GITSYNC_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.gmp_git_prometheus_rule_sync_secret.metadata[0].name
                key  = "token"
              }
            }
          }

          volume_mount {
            name       = "rules-volume"
            mount_path = "/git"
          }
        }

        container {
          name  = "${var.name}-git-prometheus-config-sync"
          image = "registry.k8s.io/git-sync/git-sync:v4.2.4"
          args = [
            "--period=120s",
            "--repo=${var.git_prometheus_config_url}",
            "--ref=${var.git_prometheus_config_ref}",
            "--root=/git",
            "--link=current",
            "--one-time=false",
          ]
          env {
            name = "GITSYNC_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.gmp_git_prometheus_config_sync_secret.metadata[0].name
                key  = "username"
              }
            }
          }
          env {
            name = "GITSYNC_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.gmp_git_prometheus_config_sync_secret.metadata[0].name
                key  = "token"
              }
            }
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/git"
          }
        }

        container {
          name = "${var.name}-gmp-rule-evaluator-otel-collector"
          # Contrib image is required as it contains the googlemanagedprometheus exporter
          image = "otel/opentelemetry-collector-contrib:latest"
          args  = ["--config=/etc/otelcol-contrib/config.yaml"]

          volume_mount {
            name       = "gmp-rule-evaluator-otel-collector-config-volume"
            mount_path = "/etc/otelcol-contrib"
          }
        }

        volume {
          name = "gmp-rule-evaluator-otel-collector-config-volume"
          config_map {
            name = kubernetes_config_map_v1.gmp_rule_evaluator_otel_config.metadata[0].name
          }
        }

        volume {
          name = "rules-volume"
          empty_dir {}
        }

        volume {
          name = "config-volume"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_secret_v1" "gmp_git_prometheus_rule_sync_secret" {

  metadata {
    name      = "${var.name}-gmp-git-prometheus-rule-sync-secret"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }

  type = "Opaque"
  data = {
    username = var.git_prometheus_rules_username
    token    = var.git_prometheus_rules_pat
  }
}


resource "kubernetes_secret_v1" "gmp_git_prometheus_config_sync_secret" {

  metadata {
    name      = "${var.name}-gmp-git-prometheus-config-sync-secret"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }

  type = "Opaque"
  data = {
    username = var.git_prometheus_config_username
    token    = var.git_prometheus_config_pat
  }
}

resource "kubernetes_secret_v1" "gmp_git_alertmanager_config_sync_secret" {

  metadata {
    name      = "${var.name}-gmp-git-alertmanager-config-sync-secret"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }

  type = "Opaque"
  data = {
    username = var.git_alertmanager_config_username
    token    = var.git_alertmanager_config_pat
  }
}

resource "kubernetes_config_map_v1" "alertmanager_otel_config" {
  metadata {
    name      = "${var.name}-alertmanager-otel-collector-config"
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
        - job_name: alertmanager
          scrape_interval: 30s
          static_configs:
            - targets: ["127.0.0.1:${local.alertmanager_web_port}"]
processors:
  batch:
    send_batch_size: 200
    timeout: 5s
  resource:
    attributes:
      - key: k8s.pod.name
        value: "$${env:K8S_POD_NAME}"
        action: upsert
      - key: k8s.namespace.name
        value: "$${env:K8S_NAMESPACE}"
        action: upsert
  resourcedetection:
    detectors: [gcp,env]
    timeout: 2s
    override: false
exporters:
  googlemanagedprometheus:
    project: "${var.project_id}"
    metric:
      resource_filters:
        - prefix: "k8s."        # Passes through k8s.pod.name, k8s.namespace.name, etc.
        # - prefix: "custom."     # Passes through any internal tag prefixes you track
        # - regex: ".*"           # ALternatively: Pass through everything (high cardinality warning!)
  debug:
    verbosity: detailed
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
      processors: [resourcedetection, resource, batch]
      exporters: [googlemanagedprometheus]
EOF
  }
}

resource "kubernetes_config_map_v1" "gmp_rule_evaluator_otel_config" {
  metadata {
    name      = "${var.name}-gmp-rule-evaluator-otel-collector-config"
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
        - job_name: gmp-rule-evaluator
          scrape_interval: 30s
          static_configs:
            - targets: ["127.0.0.1:${local.gmp_rule_evaluator_web_port}"]
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