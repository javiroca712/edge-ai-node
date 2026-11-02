# ==============================================================================
# Helper script to execute Terraform inside Docker container on dev laptop
# ==============================================================================
# Mirrors scripts/run_ansible.ps1 to keep local environment clean and zero-install.
# Usage:
#   .\scripts\run_terraform.ps1 init
#   .\scripts\run_terraform.ps1 plan
#   .\scripts\run_terraform.ps1 apply -auto-approve
# ==============================================================================

$workDir = (Get-Location).Path
$kubeDir = "$workDir\docker\k3s-control-plane\kubeconfig"

if ($args.Count -eq 0) {
    Write-Host "Usage: .\scripts\run_terraform.ps1 <command> [options]"
    Write-Host "Example: .\scripts\run_terraform.ps1 plan"
    exit 1
}

# Ensure k3s kubeconfig is accessible inside the container
docker run --rm -i `
  -v "${workDir}\terraform:/workspace" `
  -v "${kubeDir}:/root/.kube" `
  -e KUBECONFIG=/root/.kube/kubeconfig.yaml `
  -w /workspace `
  hashicorp/terraform:1.9.8 @args
