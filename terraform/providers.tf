# ==============================================================================
# Terraform Providers Configuration: Edge AI Node Cluster
# ==============================================================================
# Manages in-cluster infrastructure declaratively via Kubernetes & Helm providers.
# The control plane runs inside Docker on the dev laptop (localhost:6443).
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15.0"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}
