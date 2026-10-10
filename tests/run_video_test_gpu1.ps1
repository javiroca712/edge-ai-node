# Video Generation Test Runner for GPU 1 (PCIe 3.0 x4 bus)
# Target: GPU 1 (0000:0e:00.0, PCIe 3.0 x4 bus)
# Engine: stable-diffusion.cpp (HIPBLAS RDNA2 gfx1030)

$NodeHost = "100.104.80.65"
$User = "ai-agent"
$RemoteScript = "/home/ai-agent/run_sd_video_test_gpu1.sh"
$RemoteVideo = "/opt/ai-models/animatediff/output_eagle_test_gpu1_x4.webm"
$LocalVideo = "$PSScriptRoot\..\artifacts\output_eagle_test_gpu1_x4.webm"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Launching Video Generation Test on GPU 1 (PCIe x4) ($NodeHost)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Temporarily pause llama-api-1 to free 100% of GPU 1 VRAM
Write-Host "[1/5] Freeing GPU 1 VRAM (temporarily stopping llama-api-1)..." -ForegroundColor Yellow
ssh -n -o BatchMode=yes "$User@$NodeHost" "sudo systemctl stop llama-api-1.service"
Start-Sleep -Seconds 2

# Verify VRAM is freed
$VramCard0 = ssh -n -o BatchMode=yes "$User@$NodeHost" "cat /sys/class/drm/card0/device/mem_info_vram_used"
Write-Host "GPU 1 VRAM used: $([math]::Round($VramCard0 / 1MB, 2)) MB" -ForegroundColor Yellow

# 2. Deploy script to node
Write-Host "`n[2/5] Deploying test script to node..." -ForegroundColor Yellow
scp -B -o BatchMode=yes "$PSScriptRoot\..\scripts\run_sd_video_test_gpu1.sh" "$User@${NodeHost}:$RemoteScript"
ssh -n -o BatchMode=yes "$User@$NodeHost" "chmod +x $RemoteScript"

# 3. Execute video test on GPU 1
Write-Host "`n[3/5] Executing inference on GPU 1 (PCIe x4)..." -ForegroundColor Green
ssh -n -o BatchMode=yes "$User@$NodeHost" "bash $RemoteScript"

# 4. Restore llama-api-1 service
Write-Host "`n[4/5] Restoring llama-api-1 service..." -ForegroundColor Yellow
ssh -n -o BatchMode=yes "$User@$NodeHost" "sudo systemctl start llama-api-1.service"
Start-Sleep -Seconds 3
$Health = ssh -n -o BatchMode=yes "$User@$NodeHost" "curl -s http://127.0.0.1:8083/health"
Write-Host "Llama-api-1 service status: $Health" -ForegroundColor Green

# 5. Download generated video artifact
Write-Host "`n[5/5] Downloading generated video artifact to local machine..." -ForegroundColor Cyan
$CheckResult = ssh -n -o BatchMode=yes "$User@$NodeHost" "test -f '$RemoteVideo' && echo 'EXISTS' || echo 'MISSING'"
if ($CheckResult -match "EXISTS") {
    scp -B -o BatchMode=yes "$User@${NodeHost}:$RemoteVideo" "$LocalVideo"
    Write-Host "Video downloaded successfully: $LocalVideo" -ForegroundColor Green
    Get-Item $LocalVideo | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
} else {
    Write-Host "ERROR: Video generation did not produce $RemoteVideo" -ForegroundColor Red
}
