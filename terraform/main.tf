# ==============================================================================
# Terraform Main: Declarative Infrastructure for Edge AI Node K3s Cluster
# ==============================================================================

# 1. Kubernetes Namespace
resource "kubernetes_namespace" "edge_ai" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"    = "edge-ai-node"
      "app.kubernetes.io/part-of" = "edge-inference-platform"
    }
  }
}

# 2. Storage: Immutable Models PV & PVC
resource "kubernetes_persistent_volume" "ai_models" {
  metadata {
    name = "ai-models-pv"
    labels = {
      tier = "storage-immutable"
    }
  }
  spec {
    capacity = {
      storage = var.models_storage_capacity
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "manual"
    persistent_volume_source {
      host_path {
        path = var.models_host_path
        type = "Directory"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "ai_models" {
  metadata {
    name      = "ai-models-pvc"
    namespace = kubernetes_namespace.edge_ai.metadata[0].name
  }
  spec {
    access_modes       = ["ReadOnlyMany"]
    storage_class_name = "manual"
    resources {
      requests = {
        storage = var.models_storage_capacity
      }
    }
    volume_name = kubernetes_persistent_volume.ai_models.metadata[0].name
  }
}

# 3. Storage: Dynamic Artifacts PV & PVC
resource "kubernetes_persistent_volume" "ai_artifacts" {
  metadata {
    name = "ai-artifacts-pv"
    labels = {
      tier = "storage-dynamic"
    }
  }
  spec {
    capacity = {
      storage = var.artifacts_storage_capacity
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "manual"
    persistent_volume_source {
      host_path {
        path = var.artifacts_host_path
        type = "DirectoryOrCreate"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "ai_artifacts" {
  metadata {
    name      = "ai-artifacts-pvc"
    namespace = kubernetes_namespace.edge_ai.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "manual"
    resources {
      requests = {
        storage = var.artifacts_storage_capacity
      }
    }
    volume_name = kubernetes_persistent_volume.ai_artifacts.metadata[0].name
  }
}

# 4. AMD GPU Device Plugin DaemonSet
resource "kubernetes_daemonset" "amd_gpu_plugin" {
  metadata {
    name      = "amdgpu-device-plugin-daemonset"
    namespace = "kube-system"
    labels = {
      name = "amdgpu-device-plugin-ds"
    }
  }
  spec {
    selector {
      match_labels = {
        name = "amdgpu-device-plugin-ds"
      }
    }
    template {
      metadata {
        labels = {
          name = "amdgpu-device-plugin-ds"
        }
      }
      spec {
        priority_class_name = "system-node-critical"
        toleration {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
        }
        node_selector = {
          accelerator = "amd-rocm"
        }
        container {
          name  = "amdgpu-device-plugin"
          image = "rocm/k8s-device-plugin:latest"
          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
          volume_mount {
            name       = "device-plugin"
            mount_path = "/var/lib/kubelet/device-plugins"
          }
          volume_mount {
            name       = "dev"
            mount_path = "/dev"
          }
          volume_mount {
            name       = "sys"
            mount_path = "/sys"
          }
        }
        volume {
          name = "device-plugin"
          host_path {
            path = "/var/lib/kubelet/device-plugins"
          }
        }
        volume {
          name = "dev"
          host_path {
            path = "/dev"
          }
        }
        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }
      }
    }
  }
}

# 5. Artifact File Server (Nginx)
resource "kubernetes_config_map" "artifact_server_config" {
  metadata {
    name      = "artifact-server-config"
    namespace = kubernetes_namespace.edge_ai.metadata[0].name
  }
  data = {
    "nginx.conf" = <<-EOT
      events {
          worker_connections 256;
      }
      http {
          include /etc/nginx/mime.types;
          default_type application/octet-stream;
          sendfile on;
          tcp_nopush on;
          tcp_nodelay on;
          keepalive_timeout 65;

          server {
              listen 8085;
              server_name _;

              location /health {
                  access_log off;
                  return 200 "OK\n";
                  add_header Content-Type text/plain;
              }

              location /outputs/ {
                  alias /var/lib/ai-artifacts/outputs/;
                  autoindex on;
                  autoindex_format json;
                  add_header 'Access-Control-Allow-Origin' '*' always;
                  add_header 'Access-Control-Allow-Methods' 'GET, HEAD, OPTIONS' always;
                  add_header 'Access-Control-Allow-Headers' 'Range, Authorization, Content-Type' always;
                  add_header 'Access-Control-Expose-Headers' 'Content-Length, Content-Range' always;
                  add_header 'Accept-Ranges' 'bytes' always;

                  if ($request_method = 'OPTIONS') {
                      return 204;
                  }
              }
          }
      }
    EOT
  }
}

resource "kubernetes_deployment" "artifact_server" {
  metadata {
    name      = "artifact-server"
    namespace = kubernetes_namespace.edge_ai.metadata[0].name
    labels = {
      app  = "artifact-server"
      tier = "presentation"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "artifact-server"
      }
    }
    template {
      metadata {
        labels = {
          app = "artifact-server"
        }
      }
      spec {
        node_selector = {
          accelerator = "amd-rocm"
        }
        container {
          name              = "nginx-file-server"
          image             = "nginx:1.27-alpine"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 8085
            name           = "http-files"
          }
          resources {
            limits = {
              cpu    = "200m"
              memory = "64Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "32Mi"
            }
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8085
            }
            initial_delay_seconds = 5
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8085
            }
            period_seconds = 5
          }
          volume_mount {
            name       = "nginx-conf"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx.conf"
            read_only  = true
          }
          volume_mount {
            name       = "dynamic-artifacts"
            mount_path = "/var/lib/ai-artifacts/outputs"
            sub_path   = "outputs"
            read_only  = true
          }
        }
        volume {
          name = "nginx-conf"
          config_map {
            name = kubernetes_config_map.artifact_server_config.metadata[0].name
          }
        }
        volume {
          name = "dynamic-artifacts"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.ai_artifacts.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "artifact_server" {
  metadata {
    name      = "artifact-server"
    namespace = kubernetes_namespace.edge_ai.metadata[0].name
    labels = {
      app = "artifact-server"
    }
  }
  spec {
    type = "NodePort"
    selector = {
      app = "artifact-server"
    }
    port {
      name        = "http-files"
      port        = 8085
      target_port = 8085
      node_port   = 30085
    }
  }
}

# 6. Piper TTS Audio Synthesis Service
resource "kubernetes_deployment" "piper_tts" {
  metadata {
    name      = "piper-tts"
    namespace = kubernetes_namespace.edge_ai.metadata[0].name
    labels = {
      app  = "piper-tts"
      tier = "audio-synthesis"
    }
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        app = "piper-tts"
      }
    }
    template {
      metadata {
        labels = {
          app = "piper-tts"
        }
      }
      spec {
        node_selector = {
          accelerator = "amd-rocm"
        }
        container {
          name              = "piper-service"
          image             = "${var.container_registry}/edge-piper-tts:${var.image_tag}"
          image_pull_policy = "IfNotPresent"
          env {
            name  = "PIPER_MODEL_DIR"
            value = "/opt/ai-models/tts"
          }
          env {
            name  = "ARTIFACTS_DIR"
            value = "/var/lib/ai-artifacts"
          }
          port {
            container_port = 8084
            name           = "http-tts"
          }
          resources {
            limits = {
              cpu    = "1000m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8084
            }
            initial_delay_seconds = 15
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8084
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
          volume_mount {
            name       = "models-tts"
            mount_path = "/opt/ai-models"
            read_only  = true
          }
          volume_mount {
            name       = "artifacts-storage"
            mount_path = "/var/lib/ai-artifacts"
          }
        }
        volume {
          name = "models-tts"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.ai_models.metadata[0].name
          }
        }
        volume {
          name = "artifacts-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.ai_artifacts.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "piper_tts" {
  metadata {
    name      = "piper-tts"
    namespace = kubernetes_namespace.edge_ai.metadata[0].name
    labels = {
      app = "piper-tts"
    }
  }
  spec {
    type = "NodePort"
    selector = {
      app = "piper-tts"
    }
    port {
      name        = "http-tts"
      port        = 8084
      target_port = 8084
      node_port   = 30084
    }
  }
}

# 7. Resident LLM Inference Service (llama-server)
resource "kubernetes_deployment" "llama_server" {
  metadata {
    name      = "llama-server-dynamic"
    namespace = kubernetes_namespace.edge_ai.metadata[0].name
    labels = {
      app  = "llama-server"
      tier = "inference-gateway"
    }
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        app = "llama-server"
      }
    }
    template {
      metadata {
        labels = {
          app = "llama-server"
        }
      }
      spec {
        node_selector = {
          accelerator = "amd-rocm"
        }
        container {
          name              = "llama-server"
          image             = "${var.container_registry}/edge-llama-server:${var.image_tag}"
          image_pull_policy = "IfNotPresent"
          args = [
            "-m", "/opt/ai-models/llm/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
            "--host", "0.0.0.0",
            "--port", "8083",
            "--metrics",
            "--n-gpu-layers", "99",
            "-c", "16384"
          ]
          env {
            name  = "HSA_OVERRIDE_GFX_VERSION"
            value = "10.3.0"
          }
          port {
            container_port = 8083
            name           = "http-llm"
          }
          resources {
            limits = {
              "amd.com/gpu" = "1"
            }
          }
          security_context {
            capabilities {
              add = ["SYS_PTRACE"]
            }
          }
          startup_probe {
            http_get {
              path = "/health"
              port = 8083
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            failure_threshold     = 40
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8083
            }
            period_seconds = 15
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8083
            }
            period_seconds = 5
          }
          volume_mount {
            name       = "models-storage"
            mount_path = "/opt/ai-models"
            read_only  = true
          }
        }
        volume {
          name = "models-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.ai_models.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "llama_server" {
  metadata {
    name      = "llama-api"
    namespace = kubernetes_namespace.edge_ai.metadata[0].name
    labels = {
      app = "llama-server"
    }
  }
  spec {
    type = "NodePort"
    selector = {
      app = "llama-server"
    }
    port {
      name        = "http-llm"
      port        = 8083
      target_port = 8083
      node_port   = 30083
    }
  }
}
