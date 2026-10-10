#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "=== EDGE AI NODE VIDEO GENERATION TEST ==="
echo "Date: $(date -u)"
echo "Target: GPU 0 (PCIe 3.0 x8/x16 bus)"
echo "Engine: stable-diffusion.cpp (sd-cli with HIPBLAS gfx1030)"
echo "Model: Realistic Vision V6.0 B1 + AnimateDiff mm_sd15_v3"
echo "=========================================="

export HSA_OVERRIDE_GFX_VERSION=10.3.0
export HIP_VISIBLE_DEVICES=0

MODEL_PATH="/opt/ai-models/animatediff/realisticVisionV60B1.safetensors"
MOTION_PATH="/opt/ai-models/animatediff/mm_sd15_v3.safetensors"
OUT_VIDEO="/opt/ai-models/animatediff/output_eagle_test.webm"
SD_BIN="/opt/stable-diffusion.cpp/build/bin/sd-cli"

if [[ ! -f "$MODEL_PATH" ]]; then
    echo "ERROR: Model $MODEL_PATH not found"
    exit 1
fi
if [[ ! -f "$MOTION_PATH" ]]; then
    echo "ERROR: Motion module $MOTION_PATH not found"
    exit 1
fi
if [[ ! -x "$SD_BIN" ]]; then
    echo "ERROR: Binary $SD_BIN not found or not executable"
    exit 1
fi

rm -f "$OUT_VIDEO"

echo "[1/4] Baseline Memory Snapshot:"
free -m
echo ""

TELEMETRY_LOG="/tmp/sd_video_telemetry.log"
rm -f "$TELEMETRY_LOG"

# Launch background telemetry monitor (every 1 second)
(
    while true; do
        DATE=$(date +%T)
        MEM=$(free -m | awk '/Mem:/ {print $3 "/" $2}')
        SWAP=$(free -m | awk '/Swap:/ {print $3 "/" $2}')
        # Check DRM VRAM (card0 and card1)
        VRAM0=$(cat /sys/class/drm/card0/device/mem_info_vram_used 2>/dev/null || echo "0")
        VRAM1=$(cat /sys/class/drm/card1/device/mem_info_vram_used 2>/dev/null || echo "0")
        VRAM0_MB=$((VRAM0 / 1024 / 1024))
        VRAM1_MB=$((VRAM1 / 1024 / 1024))
        echo "[$DATE] Host RAM: ${MEM}MB | Swap: ${SWAP}MB | GPU0 VRAM: ${VRAM0_MB}MB | GPU1 VRAM: ${VRAM1_MB}MB" >> "$TELEMETRY_LOG"
        sleep 1
    done
) &
MONITOR_PID=$!

trap "kill $MONITOR_PID 2>/dev/null || true" EXIT

echo "[2/4] Executing Video Inference on GPU 0..."
START_TIME=$(date +%s%N)

"$SD_BIN" -M vid_gen \
    --model "$MODEL_PATH" \
    --motion-module "$MOTION_PATH" \
    --diffusion-fa \
    --mmap \
    -p "a majestic eagle soaring over snow-covered mountain peaks at sunset, cinematic 8k resolution, dramatic lighting, photorealistic" \
    -n "deformed, blurry, bad anatomy, bad quality, artifacts, watermark" \
    -H 512 -W 512 \
    --video-frames 16 \
    --fps 8 \
    --steps 15 \
    --cfg-scale 7.5 \
    --sampling-method euler_a \
    --scheduler discrete \
    -s 42 \
    -o "$OUT_VIDEO"

END_TIME=$(date +%s%N)
kill "$MONITOR_PID" 2>/dev/null || true

DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
DURATION_SEC=$(awk "BEGIN {print $DURATION_MS / 1000}")

echo ""
echo "[3/4] Video Inference Completed in ${DURATION_SEC} seconds!"

if [[ -f "$OUT_VIDEO" ]]; then
    SIZE=$(ls -lh "$OUT_VIDEO" | awk '{print $5}')
    echo "Generated Video Artifact: $OUT_VIDEO ($SIZE)"
else
    echo "ERROR: Video artifact $OUT_VIDEO was not created!"
    exit 1
fi

echo ""
echo "[4/4] Telemetry Summary during Generation:"
echo "--- Peak Host RAM & VRAM ---"
tail -n 25 "$TELEMETRY_LOG"
echo "=========================================="
