# 2. Alertmanager Routing and Receiver Configuration
resource "kubernetes_config_map_v1" "alertmanager_config" {

  metadata {
    name      = "${var.name}-alertmanager-config"
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
        container {
          name  = "${var.name}-alertmanager"
          image = "quay.io/prometheus/alertmanager:v0.27.0"

          args = [
            "--config.file=/etc/alertmanager/alertmanager.yml",
            "--storage.path=/alertmanager",
            # 2. Point to the headless service DNS pattern to find cluster siblings
            "--cluster.peer=dev-alertmanager-0.dev-alertmanager.${kubernetes_namespace_v1.observability_namespace.metadata[0].name}.svc.cluster.local:9094",
            "--cluster.peer=dev-alertmanager-1.dev-alertmanager.${kubernetes_namespace_v1.observability_namespace.metadata[0].name}.svc.cluster.local:9094",
            "--cluster.peer=dev-alertmanager-2.dev-alertmanager.${kubernetes_namespace_v1.observability_namespace.metadata[0].name}.svc.cluster.local:9094"
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
            "-watched-dir=/etc/alertmanager",
            "-reload-url=http://127.0.0.1:9093/-/reload",
            "-ready-url=http://127.0.0.1:9093/-/ready"
          ]

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/alertmanager"
          }
        }

        volume {
          name = "config-volume"
          config_map {
            name = kubernetes_config_map_v1.alertmanager_config.metadata[0].name
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


# # 3. ConfigMap containing your raw Prometheus config
# resource "kubernetes_config_map_v1" "gmp_rule_evaluator_config" {
#   metadata {
#     name      = "${var.name}-rule-evaluator-prometheus-yaml"
#     namespace = kubernetes_namespace_v1.observability_namespace.metadata[0].name
#   }
#
#   data = {
#     "prometheus.yaml" = <<EOF
# global:
#   scrape_interval: 15s
#   evaluation_interval: 15s
#
# rule_files:
#   - /etc/rules/current/*.yaml
#
# alerting:
#   alertmanagers:
#     - static_configs:
#         - targets:
#             - dev-alertmanager.${kubernetes_namespace_v1.observability_namespace.metadata[0].name}.svc.cluster.local:9093
# EOF
#   }
# }


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
            "--log.level=info"
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
            "-reload-url=http://127.0.0.1:9091/-/reload",
            "-ready-url=http://127.0.0.1:9091/-/ready"
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
            "--period=30s",
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