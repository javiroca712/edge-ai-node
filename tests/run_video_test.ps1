# Video Generation Test Runner for Edge AI Node
# Target: GPU 0 (PCIe 3.0 x8/x16 bus)
# Engine: stable-diffusion.cpp (HIPBLAS RDNA2 gfx1030)

$NodeHost = "100.104.80.65"
$User = "ai-agent"
$RemoteScript = "/home/ai-agent/run_sd_video_test.sh"
$RemoteVideo = "/opt/ai-models/animatediff/output_eagle_test.webm"
$LocalVideo = "$PSScriptRoot\..\artifacts\output_eagle_test.webm"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Launching Video Generation Test on Edge Node ($NodeHost)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Ensure artifacts directory exists
$ArtifactsDir = Split-Path $LocalVideo -Parent
if (-not (Test-Path $ArtifactsDir)) {
    New-Item -ItemType Directory -Path $ArtifactsDir -Force | Out-Null
}

# 2. Execute test script on node
ssh -n -o BatchMode=yes "$User@$NodeHost" "bash $RemoteScript"

# 3. Check if output video was generated and copy locally
$CheckResult = ssh -n -o BatchMode=yes "$User@$NodeHost" "test -f '$RemoteVideo' && echo 'EXISTS' || echo 'MISSING'"
if ($CheckResult -match "EXISTS") {
    Write-Host "`nDownloading generated video artifact to local machine..." -ForegroundColor Green
    scp -o BatchMode=yes "$User@${NodeHost}:$RemoteVideo" "$LocalVideo"
    Write-Host "Video downloaded successfully: $LocalVideo" -ForegroundColor Green
    Get-Item $LocalVideo | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
} else {
    Write-Host "`nERROR: Video generation did not produce $RemoteVideo" -ForegroundColor Red
}
