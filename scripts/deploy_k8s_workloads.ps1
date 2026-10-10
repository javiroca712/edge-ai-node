# Script to deploy, scale, and orchestrate K3s workloads on Edge Nodes
param (
    [string]$Action = "status",   # "deploy-plugin", "deploy-dynamic-llm", "scale-llm", "run-dynamic-video", "status"
    [int]$Replicas = 1
)

$K8sDir = "$PSScriptRoot\..\k8s"

function Run-Kubectl {
    param([string]$Cmd)
    docker exec k3s-control-plane sh -c "kubectl $Cmd"
}

switch ($Action) {
    "deploy-plugin" {
        Write-Host "Deploying AMD GPU Device Plugin DaemonSet..." -ForegroundColor Cyan
        Get-Content "$K8sDir\amd_gpu_device_plugin.yaml" | docker exec -i k3s-control-plane kubectl apply -f -
        Write-Host "Waiting for device plugin daemonset..." -ForegroundColor Yellow
        Run-Kubectl "rollout status daemonset/amdgpu-device-plugin-daemonset -n kube-system --timeout=60s"
        Write-Host "AMD Device Plugin is active! Checking allocatable GPUs..." -ForegroundColor Green
        Run-Kubectl "get nodes -o custom-columns=NAME:.metadata.name,GPUS:.status.allocatable.'amd\.com/gpu'"
    }
    "deploy-dynamic-llm" {
        Write-Host "Deploying Dynamic LLM Server (requesting amd.com/gpu: 1)..." -ForegroundColor Cyan
        # If legacy llama-server-gpu1 is running, clean it up
        docker exec k3s-control-plane kubectl delete deployment llama-server-gpu1 --ignore-not-found=true | Out-Null
        docker exec k3s-control-plane kubectl delete service llama-api-gpu1 --ignore-not-found=true | Out-Null
        
        Get-Content "$K8sDir\llama_server_dynamic.yaml" | docker exec -i k3s-control-plane kubectl apply -f -
        Write-Host "Waiting for dynamic llama-server pod readiness (startupProbe)..." -ForegroundColor Yellow
        Run-Kubectl "rollout status deployment/llama-server-dynamic --timeout=240s"
        Write-Host "Dynamic LLM Server ready! Testing /health..." -ForegroundColor Green
        Invoke-RestMethod -Uri "http://100.104.80.65:8083/health"
    }
    "scale-llm" {
        Write-Host "Scaling llama-server-dynamic to $Replicas replicas (on-demand resource management)..." -ForegroundColor Cyan
        Run-Kubectl "scale deployment/llama-server-dynamic --replicas=$Replicas"
        if ($Replicas -gt 0) {
            Write-Host "Waiting for rollout..." -ForegroundColor Yellow
            Run-Kubectl "rollout status deployment/llama-server-dynamic --timeout=150s"
        } else {
            Write-Host "GPU VRAM released from LLM server!" -ForegroundColor Green
        }
    }
    "run-dynamic-video" {
        Write-Host "Submitting Dynamic Video Generation Job (requesting amd.com/gpu: 1)..." -ForegroundColor Cyan
        Run-Kubectl "delete job video-gen-dynamic --ignore-not-found=true" | Out-Null
        Get-Content "$K8sDir\video_gen_dynamic_job.yaml" | docker exec -i k3s-control-plane kubectl apply -f -
        Write-Host "Job submitted! Waiting for completion..." -ForegroundColor Yellow
        Run-Kubectl "wait --for=condition=complete job/video-gen-dynamic --timeout=300s"
        Write-Host "Video generation completed successfully!" -ForegroundColor Green
    }
    "status" {
        Write-Host "=== K3s Cluster Hardware & GPU Capacity ===" -ForegroundColor Cyan
        Run-Kubectl "get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,ROLES:.metadata.labels.'node-role\.kubernetes\.io/master',GPUS:.status.allocatable.'amd\.com/gpu',BUS_SLOT0:.metadata.labels.'gpu\.amd\.com/slot0\.bus',BUS_SLOT1:.metadata.labels.'gpu\.amd\.com/slot1\.bus'"
        Write-Host "`n=== Deployments & Pods ===" -ForegroundColor Cyan
        Run-Kubectl "get deployments,pods,jobs -o wide"
    }
}
