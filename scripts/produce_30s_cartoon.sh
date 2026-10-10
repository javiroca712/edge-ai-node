#!/usr/bin/env bash
# ==============================================================================
# Dual-GPU Parallel Production Pipeline: 30s 720p 30fps Cartoon Animation
# Uses ToonYou Beta6 + AnimateDiff Motion Module + Piper TTS + FFmpeg
# Dispatches shots concurrently across GPU 0 (PCIe x8) and GPU 1 (PCIe x4)
# ==============================================================================
set -euo pipefail

MODEL_DIR="/opt/ai-models/animatediff"
WORK_DIR="${MODEL_DIR}/cartoon_project"
VOICE_DIR="${MODEL_DIR}/voices"
SD_BIN="/opt/stable-diffusion.cpp/build/bin/sd-cli"
OUTPUT_FINAL="${MODEL_DIR}/cartoon_30s_720p_30fps.mp4"

# Use ToonYou if available, fallback to RealisticVision
MODEL_PATH="${MODEL_DIR}/toonyou_beta6.safetensors"
if [[ ! -f "$MODEL_PATH" ]]; then
    MODEL_PATH="${MODEL_DIR}/realisticVisionV60B1.safetensors"
fi
MOTION_MODULE="${MODEL_DIR}/mm_sd15_v3.safetensors"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "=========================================================="
echo "=== PRODUCING 30s 720p 30fps CARTOON ANIMATION ==="
echo "Model: $(basename "$MODEL_PATH")"
echo "Motion Module: $(basename "$MOTION_MODULE")"
echo "Timestamp: $(date -u)"
echo "=========================================================="

# Define style and character tokens
STYLE="masterpiece, best quality, cartoon animation style, vibrant colors, 3D Pixar style, clean lines, expressive, cinematic lighting"
NEG_PROMPT="photorealistic, real life photo, deformed, distorted, blurry, bad anatomy, bad quality, artifacts, watermark, lowres, ugly"

# Function to render a shot on a specific GPU
render_shot() {
    local SHOT_ID="$1"
    local GPU_ID="$2"
    local PROMPT="$3"
    local OUT_FILE="${WORK_DIR}/shot_${SHOT_ID}_raw.webm"
    
    if [[ -f "$OUT_FILE" && -s "$OUT_FILE" ]]; then
        echo "[GPU ${GPU_ID}] Shot ${SHOT_ID} already rendered ($(ls -lh "$OUT_FILE" | awk '{print $5}')), skipping."
        return 0
    fi
    
    echo "[GPU ${GPU_ID}] Starting Shot ${SHOT_ID} rendering..."
    HIP_VISIBLE_DEVICES="${GPU_ID}" HSA_OVERRIDE_GFX_VERSION="10.3.0" LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu" \
    "$SD_BIN" -M vid_gen \
        --model "$MODEL_PATH" \
        --motion-module "$MOTION_MODULE" \
        --diffusion-fa \
        --mmap \
        -p "${STYLE}, ${PROMPT}" \
        -n "$NEG_PROMPT" \
        -H 512 -W 512 \
        --video-frames 16 \
        --fps 8 \
        --steps 14 \
        --cfg-scale 7.0 \
        --sampling-method euler_a \
        --scheduler discrete \
        -s $(( 42 + SHOT_ID * 17 )) \
        -o "$OUT_FILE" > "${WORK_DIR}/shot_${SHOT_ID}.log" 2>&1
    
    echo "[GPU ${GPU_ID}] Completed Shot ${SHOT_ID}."
}

# ------------------------------------------------------------------------------
# Parallel Rendering across Dual GPUs:
# Batch 1: Shots 1 & 2
# ------------------------------------------------------------------------------
echo "--- Rendering Batch 1 (Shots 1 & 2) ---"
P1="wide angle view, high-tech cartoon launchpad at sunset, cute small round retro blue robot with glowing cyan eyes standing next to sleek miniature silver rocket, golden clouds"
P2="close-up portrait, cheerful young girl pilot, aviator goggles on forehead, bright yellow jacket, short brown bob hair, warm confident smile, mission control screens background"

render_shot 1 0 "$P1" &
PID1=$!
render_shot 2 1 "$P2" &
PID2=$!
wait $PID1
wait $PID2

# ------------------------------------------------------------------------------
# Batch 2: Shots 3 & 4
# ------------------------------------------------------------------------------
echo "--- Rendering Batch 2 (Shots 3 & 4) ---"
P3="medium shot, cute small round retro blue robot with glowing cyan eyes pulling a glowing retro control lever, colorful energy sparks, flashing dashboard lights, happy excited"
P4="cinematic low angle, sleek miniature silver spaceship launching from platform, bright rainbow booster exhaust flame, billowing clouds of fluffy cartoon smoke, launch blastoff"

render_shot 3 0 "$P3" &
PID3=$!
render_shot 4 1 "$P4" &
PID4=$!
wait $PID3
wait $PID4

# ------------------------------------------------------------------------------
# Batch 3: Shots 5 & 6
# ------------------------------------------------------------------------------
echo "--- Rendering Batch 3 (Shots 5 & 6) ---"
P5="tracking shot, sleek miniature silver rocket soaring upwards through golden clouds, beautiful orange sunset sky, dynamic motion trails"
P6="close-up, cute small round retro blue robot waving happily through glass spaceship dome window, joyful star-shaped glowing eyes, spaceship interior"

render_shot 5 0 "$P5" &
PID5=$!
render_shot 6 1 "$P6" &
PID6=$!
wait $PID5
wait $PID6

# ------------------------------------------------------------------------------
# Batch 4: Shots 7 & 8
# ------------------------------------------------------------------------------
echo "--- Rendering Batch 4 (Shots 7 & 8) ---"
P7="cinematic wide view, sleek spaceship entering twilight space orbit above glowing cartoon planet Earth, sparkling stars, vibrant aurora borealis atmosphere"
P8="wide cinematic view, glowing cartoon star constellation forming in deep starfield, celestial cosmic glow, title card background, peaceful beautiful space"

render_shot 7 0 "$P7" &
PID7=$!
render_shot 8 1 "$P8" &
PID8=$!
wait $PID7
wait $PID8

echo "=========================================================="
echo "=== ALL 8 SHOTS RENDERED! POST-PROCESSING & SMOOTHING ==="
echo "=========================================================="

# Durations for each shot (total 30 seconds):
# Shot 1: 4.0s (Byte dialogue)
# Shot 2: 4.0s (Maya dialogue)
# Shot 3: 3.5s (Byte dialogue)
# Shot 4: 3.5s (Blastoff SFX)
# Shot 5: 3.5s (Maya dialogue)
# Shot 6: 4.0s (Byte dialogue)
# Shot 7: 4.0s (Maya dialogue)
# Shot 8: 3.5s (Outro / Stars)
DURS=(4.0 4.0 3.5 3.5 3.5 4.0 4.0 3.5)
AUDIO_FILES=(
    "${VOICE_DIR}/shot1_byte.wav"
    "${VOICE_DIR}/shot2_maya.wav"
    "${VOICE_DIR}/shot3_byte.wav"
    ""
    "${VOICE_DIR}/shot5_maya.wav"
    "${VOICE_DIR}/shot6_byte.wav"
    "${VOICE_DIR}/shot7_maya.wav"
    ""
)

# Process each shot: loop/interpolate to 30fps @ 720p (1280x720) and attach audio
rm -f "${WORK_DIR}/concat_list.txt"

for idx in {0..7}; do
    SHOT_NUM=$((idx + 1))
    DUR="${DURS[$idx]}"
    RAW="${WORK_DIR}/shot_${SHOT_NUM}_raw.webm"
    PROCESSED="${WORK_DIR}/shot_${SHOT_NUM}_720p.mp4"
    AUD="${AUDIO_FILES[$idx]}"
    
    echo "Processing Shot ${SHOT_NUM} (Duration: ${DUR}s)..."
    
    # Scale to 720p (1280x720), interpolate/smooth to 30fps, loop to exact duration
    if [[ -n "$AUD" && -f "$AUD" ]]; then
        ffmpeg -y -stream_loop 2 -i "$RAW" -i "$AUD" \
            -filter_complex "[0:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,fps=30,trim=duration=${DUR}[v];[1:a]atrim=duration=${DUR},apad=whole_dur=${DUR}[a]" \
            -map "[v]" -map "[a]" \
            -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p \
            -c:a aac -b:a 192k \
            "$PROCESSED"
    else
        # Silent shot: generate synthetic subtle ambient tone
        ffmpeg -y -stream_loop 2 -i "$RAW" \
            -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
            -filter_complex "[0:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,fps=30,trim=duration=${DUR}[v];[1:a]atrim=duration=${DUR}[a]" \
            -map "[v]" -map "[a]" \
            -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p \
            -c:a aac -b:a 192k \
            "$PROCESSED"
    fi
    
    echo "file '${PROCESSED}'" >> "${WORK_DIR}/concat_list.txt"
done

echo "=== Concatenating 8 shots into Final 30s 720p 30fps Video ==="
ffmpeg -y -f concat -safe 0 -i "${WORK_DIR}/concat_list.txt" \
    -c:v copy -c:a aac -b:a 192k \
    "$OUTPUT_FINAL"

echo "=========================================================="
echo "=== PRODUCTION COMPLETED: ${OUTPUT_FINAL} ==="
ls -lh "$OUTPUT_FINAL"
ffprobe -i "$OUTPUT_FINAL" -show_entries format=duration,size -v quiet -of json
echo "=========================================================="
