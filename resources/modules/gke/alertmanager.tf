# 2. Alertmanager Routing and Receiver Configuration
resource "kubernetes_config_map_v1" "alertmanager_config" {

  metadata {
    name      = "alertmanager-config"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }

  data = {
    "alertmanager.yml" = <<EOF
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  receiver: 'default'

receivers:
- name: 'default'
EOF
  }
}

# 3. Headless Service for StatefulSet Sticky Network Identity
resource "kubernetes_service_v1" "alertmanager_service" {
  metadata {
    name      = "alertmanager"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
    labels = {
      app = "alertmanager"
    }
  }

  spec {
    selector = {
      app = "alertmanager"
    }

    port {
      name        = "web"
      port        = 9093
      target_port = 9093
    }

    port {
      name        = "mesh"
      port        = 9094
      target_port = 9094
    }

    # "None" defines it as headless, creating direct DNS paths for each pod instance
    cluster_ip = "None"
  }
}

# 4. Alertmanager StatefulSet Deployment
resource "kubernetes_stateful_set_v1" "alertmanager" {
  metadata {
    name      = "alertmanager"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }

  spec {
    service_name = kubernetes_service_v1.alertmanager_service.metadata[0].name
    replicas     = 3

    selector {
      match_labels = {
        app = "alertmanager"
      }
    }

    template {
      metadata {
        labels = {
          app = "alertmanager"
        }
      }

      spec {
        container {
          name  = "alertmanager"
          image = "quay.io/prometheus/alertmanager:v0.27.0"

          args = [
            "--config.file=/etc/alertmanager/alertmanager.yml",
            "--storage.path=/alertmanager",
            # 2. Point to the headless service DNS pattern to find cluster siblings
            "--cluster.peer=alertmanager-0.alertmanager.monitoring.svc.cluster.local:9094",
            "--cluster.peer=alertmanager-1.alertmanager.monitoring.svc.cluster.local:9094",
            "--cluster.peer=alertmanager-2.alertmanager.monitoring.svc.cluster.local:9094"
          ]

          port {
            name           = "web"
            container_port = 9093
          }

          port {
            name           = "mesh"
            container_port = 9094
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/alertmanager"
          }

          volume_mount {
            name       = "alertmanager-storage"
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

        volume {
          name = "config-volume"
          config_map {
            name = kubernetes_config_map_v1.alertmanager_config.metadata[0].name
          }
        }
      }
    }

    # Dynamically spins up dedicated persistent cloud disks per Pod replica
    volume_claim_template {
      metadata {
        name = "alertmanager-storage"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "standard-rwo" # Adjust to match your cloud's block storage class (e.g., premium-rwo)
        resources {
          requests = {
            storage = "16Mb"
          }
        }
      }
    }
  }
}

# 2. Kubernetes Service Account with Workload Identity Annotation
resource "kubernetes_service_account_v1" "gmp_rule_evaluator_ksa" {
  metadata {
    name      = "${var.name}-gmp-rule-evaluator-ksa"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.rule_evaluator_gsa.email
    }
  }
}

# 3. ConfigMap containing your raw Prometheus rules file
resource "kubernetes_config_map_v1" "gmp_rule_evaluator_rules" {
  metadata {
    name      = "rule-evaluator-rules"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }

  data = {
    "rules.yaml" = <<EOF
groups:
  - name: self-hosted-rules
    rules:
      - alert: HostHighCpuLoad
        expr: instance:node_cpu_utilisation:rate5m > 0.90
        for: 2m
        labels:
          severity: warning
EOF
  }
}

# 4. Standalone Rule Evaluator Deployment
resource "kubernetes_deployment_v1" "gmp_rule_evaluator" {
  metadata {
    name      = "gmp-rule-evaluator"
    namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
  }

  spec {
    replicas = 1 # Must be exactly 1 to avoid duplicate evaluation/alert firing rings

    selector {
      match_labels = {
        app = "gmp-rule-evaluator"
      }
    }

    template {
      metadata {
        labels = {
          app = "gmp-rule-evaluator"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.gmp_rule_evaluator_ksa.metadata[0].name

        container {
          name  = "evaluator"
          image = "gke.gcr.io/prometheus-engine/rule-evaluator:v0.17.2-gke.2"

          args = [
            "--project-id=YOUR_GCP_PROJECT_ID",
            "--rules=/etc/rules/rules.yaml",
            # Point this directly to your Alertmanager service address
            "--alertmanager.notification-queue-capacity=10000",
            "--alertmanager.url=http://alertmanager.monitoring.svc.cluster.local:9093"
          ]

          volume_mount {
            name       = "rules-volume"
            mount_path = "/etc/rules"
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

        volume {
          name = "rules-volume"
          config_map {
            name = kubernetes_config_map_v1.gmp_rule_evaluator_rules.metadata[0].name
          }
        }
      }
    }
  }
}