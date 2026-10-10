# K3s Containerized Video Generation Runner for Dual-GPU Edge Node
# Runs K3s Jobs on GPU 0 (PCIe x8) and GPU 1 (PCIe x4)

$NodeHost = "100.104.80.65"
$User = "ai-agent"
$ManifestGpu0 = "$PSScriptRoot\..\k8s\video_gen_job_gpu0.yaml"
$ManifestGpu1 = "$PSScriptRoot\..\k8s\video_gen_job_gpu1.yaml"
$ArtifactsDir = "$PSScriptRoot\..\artifacts"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " K3S DUAL-GPU CONTAINERIZED VIDEO GENERATION TEST RUNNER" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Ensure artifacts directory exists
if (-not (Test-Path $ArtifactsDir)) {
    New-Item -ItemType Directory -Path $ArtifactsDir -Force | Out-Null
}

# -------------------------------------------------------------
# PHASE 1: Run K3s Job on GPU 0 (PCIe 3.0 x8)
# -------------------------------------------------------------
Write-Host "`n[PHASE 1] Launching K3s Job on GPU 0 (PCIe x8)..." -ForegroundColor Green
docker exec k3s-control-plane kubectl delete job video-gen-gpu0-x8 --ignore-not-found=true 2>$null | Out-Null
Get-Content $ManifestGpu0 | docker exec -i k3s-control-plane kubectl apply -f -

Write-Host "Waiting for GPU 0 Job Pod to start..." -ForegroundColor Yellow
$PodName0 = ""
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    $PodName0 = (docker exec k3s-control-plane kubectl get pods -l job-name=video-gen-gpu0-x8 -o jsonpath="{.items[0].metadata.name}" 2>$null)
    if ($PodName0) { break }
}

Write-Host "GPU 0 Job Pod: $PodName0" -ForegroundColor Cyan
Write-Host "Waiting for Job completion (monitoring execution)..." -ForegroundColor Yellow

# Wait for job completion
docker exec k3s-control-plane kubectl wait --for=condition=complete job/video-gen-gpu0-x8 --timeout=300s

# Fetch container logs via crictl on node
$ContainerId0 = ssh -n -o BatchMode=yes "$User@$NodeHost" "sudo k3s crictl ps -a --name sd-video-runner | head -n 2 | tail -n 1 | awk '{print `$1}'"
Write-Host "`n--- Container Output (GPU 0) ---" -ForegroundColor Green
ssh -n -o BatchMode=yes "$User@$NodeHost" "sudo k3s crictl logs $ContainerId0 | tail -n 15"

# Download video artifact
$RemoteVideo0 = "/opt/ai-models/animatediff/k8s_output_eagle_gpu0.webm"
$LocalVideo0 = "$ArtifactsDir\k8s_output_eagle_gpu0.webm"
scp -B -o BatchMode=yes "$User@${NodeHost}:$RemoteVideo0" "$LocalVideo0"
Write-Host "GPU 0 Artifact Downloaded: $LocalVideo0" -ForegroundColor Green

# -------------------------------------------------------------
# PHASE 2: Run K3s Job on GPU 1 (PCIe 3.0 x4)
# -------------------------------------------------------------
Write-Host "`n[PHASE 2] Launching K3s Job on GPU 1 (PCIe x4)..." -ForegroundColor Green
Write-Host "Pausing llama-api-1 service to free GPU 1 VRAM..." -ForegroundColor Yellow
ssh -n -o BatchMode=yes "$User@$NodeHost" "sudo systemctl stop llama-api-1.service"
Start-Sleep -Seconds 2

docker exec k3s-control-plane kubectl delete job video-gen-gpu1-x4 --ignore-not-found=true 2>$null | Out-Null
Get-Content $ManifestGpu1 | docker exec -i k3s-control-plane kubectl apply -f -

Write-Host "Waiting for GPU 1 Job Pod to start..." -ForegroundColor Yellow
$PodName1 = ""
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    $PodName1 = (docker exec k3s-control-plane kubectl get pods -l job-name=video-gen-gpu1-x4 -o jsonpath="{.items[0].metadata.name}" 2>$null)
    if ($PodName1) { break }
}

Write-Host "GPU 1 Job Pod: $PodName1" -ForegroundColor Cyan
Write-Host "Waiting for Job completion (monitoring execution)..." -ForegroundColor Yellow

# Wait for job completion
docker exec k3s-control-plane kubectl wait --for=condition=complete job/video-gen-gpu1-x4 --timeout=300s

# Fetch container logs via crictl on node
$ContainerId1 = ssh -n -o BatchMode=yes "$User@$NodeHost" "sudo k3s crictl ps -a --name sd-video-runner | head -n 2 | tail -n 1 | awk '{print `$1}'"
Write-Host "`n--- Container Output (GPU 1) ---" -ForegroundColor Green
ssh -n -o BatchMode=yes "$User@$NodeHost" "sudo k3s crictl logs $ContainerId1 | tail -n 15"

# Restore llama-api-1 service
Write-Host "`nRestoring llama-api-1 service..." -ForegroundColor Yellow
ssh -n -o BatchMode=yes "$User@$NodeHost" "sudo systemctl start llama-api-1.service"

# Download video artifact
$RemoteVideo1 = "/opt/ai-models/animatediff/k8s_output_eagle_gpu1.webm"
$LocalVideo1 = "$ArtifactsDir\k8s_output_eagle_gpu1.webm"
scp -B -o BatchMode=yes "$User@${NodeHost}:$RemoteVideo1" "$LocalVideo1"
Write-Host "GPU 1 Artifact Downloaded: $LocalVideo1" -ForegroundColor Green

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " Both K3s Containerized Jobs Completed Successfully!" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Get-Item "$ArtifactsDir\k8s_output_eagle_*.webm" | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
