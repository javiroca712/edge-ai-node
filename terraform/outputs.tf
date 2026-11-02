# ==============================================================================
# Terraform Outputs: Edge AI Node Cluster
# ==============================================================================

output "namespace" {
  description = "Kubernetes namespace for edge AI workloads"
  value       = kubernetes_namespace.edge_ai.metadata[0].name
}

output "artifact_server_endpoint" {
  description = "HTTP URL for the Artifact File Server (NodePort)"
  value       = "http://${var.edge_node_host}:30085/outputs/"
}

output "piper_tts_endpoint" {
  description = "HTTP URL for Piper TTS audio synthesis microservice (NodePort)"
  value       = "http://${var.edge_node_host}:30084"
}

output "llama_server_endpoint" {
  description = "HTTP URL for LLaMA server OpenAI-compatible API (NodePort)"
  value       = "http://${var.edge_node_host}:30083/v1"
}
