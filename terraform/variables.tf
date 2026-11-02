# ==============================================================================
# Terraform Variables: Edge AI Node Cluster
# ==============================================================================

variable "kubeconfig_path" {
  description = "Path to the K3s cluster kubeconfig file"
  type        = string
  default     = "/root/.kube/kubeconfig.yaml"
}

variable "namespace" {
  description = "Kubernetes namespace for edge AI workloads"
  type        = string
  default     = "edge-ai-node"
}

variable "edge_node_host" {
  description = "IP address or hostname of the bare-metal edge node"
  type        = string
  default     = "100.104.80.65"
}

variable "models_host_path" {
  description = "Host directory path for static, immutable model weights on edge node"
  type        = string
  default     = "/opt/ai-models"
}

variable "artifacts_host_path" {
  description = "Host directory path for dynamic scratch and outputs on edge node"
  type        = string
  default     = "/var/lib/ai-artifacts"
}

variable "models_storage_capacity" {
  description = "Persistent volume capacity for model storage"
  type        = string
  default     = "100Gi"
}

variable "artifacts_storage_capacity" {
  description = "Persistent volume capacity for dynamic artifacts storage"
  type        = string
  default     = "50Gi"
}

variable "container_registry" {
  description = "Container registry for edge microservice images"
  type        = string
  default     = "ghcr.io/javiroca712"
}

variable "image_tag" {
  description = "Container image tag version"
  type        = string
  default     = "latest"
}

variable "deploy_observability_stack" {
  description = "Whether to deploy the Prometheus and Grafana Helm chart"
  type        = bool
  default     = true
}

variable "grafana_admin_password" {
  description = "Initial admin password for Grafana"
  type        = string
  default     = "admin"
  sensitive   = true
}
