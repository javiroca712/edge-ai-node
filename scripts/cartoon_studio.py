#!/usr/bin/env python3
"""
==============================================================================
Client Application: Cartoon Studio Pipeline Orchestrator
==============================================================================
Orchestrates end-to-end 30s cartoon production strictly via K3s containerized
services and dynamic Kubernetes batch jobs. Zero payloads run on the base OS.

Workflow:
  1. Script / Dialogue: Queries LiteLLM (localhost:4000) or llama-server (100.104.80.65:8083)
  2. Voice Synthesis: Calls containerized Piper TTS (100.104.80.65:8084/v1/synthesize)
  3. Video Generation: Dispatches containerized ROCm AnimateDiff Job to K3s
  4. Media Assembly: Dispatches containerized FFmpeg CPU Job (720p 30fps + audio mux)
  5. Download: Retrieves final MP4 & metadata via artifact-server (100.104.80.65:8085)
==============================================================================
"""

import os
import sys
import time
import json
import uuid
import datetime
import subprocess
import urllib.request
import urllib.error

EDGE_NODE_HOST = os.getenv("EDGE_NODE_HOST", "100.104.80.65")
LITELLM_URL = os.getenv("LITELLM_URL", "http://localhost:4000/v1")
LLAMA_DIRECT_URL = f"http://{EDGE_NODE_HOST}:8083/v1"
PIPER_URL = f"http://{EDGE_NODE_HOST}:8084"
ARTIFACT_URL = f"http://{EDGE_NODE_HOST}:8085"

# 8 Pre-scripted Cartoon Shots
SHOTS = [
    {
        "id": 1,
        "speaker": "Byte",
        "voice": "en_US-bryce-medium",
        "dialogue": "Systems nominal! Launch sequence initiated, Captain Maya!",
        "prompt": "wide angle view, high-tech cartoon launchpad at sunset, cute small round retro blue robot with glowing cyan eyes standing next to sleek miniature silver rocket, golden clouds",
        "duration": 4.0
    },
    {
        "id": 2,
        "speaker": "Maya",
        "voice": "en_US-lessac-medium",
        "dialogue": "Engines to maximum thrust. Next stop: the stars!",
        "prompt": "close-up portrait, cheerful young girl pilot, aviator goggles on forehead, bright yellow jacket, short brown bob hair, warm confident smile, mission control screens background",
        "duration": 4.0
    },
    {
        "id": 3,
        "speaker": "Byte",
        "voice": "en_US-bryce-medium",
        "dialogue": "Holding countdown: three, two, one, blastoff!",
        "prompt": "medium shot, cute small round retro blue robot with glowing cyan eyes pulling a glowing retro control lever, colorful energy sparks, flashing dashboard lights, happy excited",
        "duration": 3.5
    },
    {
        "id": 4,
        "speaker": None,
        "voice": None,
        "dialogue": "",
        "prompt": "cinematic low angle, sleek miniature silver spaceship launching from platform, bright rainbow booster exhaust flame, billowing clouds of fluffy cartoon smoke, launch blastoff",
        "duration": 3.5
    },
    {
        "id": 5,
        "speaker": "Maya",
        "voice": "en_US-lessac-medium",
        "dialogue": "Breaking through the stratosphere! Look at that horizon!",
        "prompt": "tracking shot, sleek miniature silver rocket soaring upwards through golden clouds, beautiful orange sunset sky, dynamic motion trails",
        "duration": 3.5
    },
    {
        "id": 6,
        "speaker": "Byte",
        "voice": "en_US-bryce-medium",
        "dialogue": "Artificial gravity engaged. We have achieved orbit!",
        "prompt": "close-up, cute small round retro blue robot waving happily through glass spaceship dome window, joyful star-shaped glowing eyes, spaceship interior",
        "duration": 4.0
    },
    {
        "id": 7,
        "speaker": "Maya",
        "voice": "en_US-lessac-medium",
        "dialogue": "Setting coordinates for the Andromeda sector. Adventure awaits!",
        "prompt": "cinematic wide view, sleek spaceship entering twilight space orbit above glowing cartoon planet Earth, sparkling stars, vibrant aurora borealis atmosphere",
        "duration": 4.0
    },
    {
        "id": 8,
        "speaker": None,
        "voice": None,
        "dialogue": "",
        "prompt": "wide cinematic view, glowing cartoon star constellation forming in deep starfield, celestial cosmic glow, title card background, peaceful beautiful space",
        "duration": 3.5
    }
]

def run_kubectl(cmd: str):
    """Executes kubectl command on local dev machine via k3s-control-plane docker container."""
    full_cmd = f'docker exec k3s-control-plane sh -c "kubectl {cmd}"'
    res = subprocess.run(full_cmd, shell=True, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"kubectl failed:\n{res.stderr}")
    return res.stdout


def synthesize_voices(task_id: str):
    print(f"\n[Step 1/4] Synthesizing voices via containerized Piper TTS ({PIPER_URL})...")
    for shot in SHOTS:
        if not shot["dialogue"]:
            print(f"  - Shot {shot['id']}: (Silent SFX/Atmosphere) - skipped TTS")
            continue

        payload = {
            "task_id": task_id,
            "shot_id": shot["id"],
            "text": shot["dialogue"],
            "voice": shot["voice"]
        }
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            f"{PIPER_URL}/v1/synthesize",
            data=data,
            headers={"Content-Type": "application/json"}
        )

        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                res = json.loads(resp.read().decode("utf-8"))
                print(f"  + Shot {shot['id']} ({shot['speaker']}): synthesized {res['duration_seconds']}s audio -> {res['output_path']}")
        except Exception as e:
            print(f"  ! Error synthesizing shot {shot['id']}: {e}")
            raise

def submit_diffusion_job(task_id: str):
    print(f"\n[Step 2/4] Checking/Dispatching Video Diffusion Job to K3s cluster...")
    check = subprocess.run(
        'docker exec k3s-control-plane sh -c "kubectl get job sd-diffusion-job --no-headers"',
        shell=True, capture_output=True, text=True
    )

    if check.returncode != 0 or "sd-diffusion-job" not in check.stdout:
        print("  + Submitting new sd-diffusion-job...")
        job_manifest = f"""
apiVersion: batch/v1
kind: Job
metadata:
  name: sd-diffusion-job
spec:
  ttlSecondsAfterFinished: 600
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      nodeSelector:
        accelerator: amd-rocm
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: gpu.amd.com/has-fastbus
                operator: In
                values: ["true"]
      containers:
      - name: sd-video-runner
        image: ubuntu:latest
        resources:
          limits:
            amd.com/gpu: 1
        securityContext:
          capabilities:
            add: ["SYS_PTRACE"]
        env:
        - name: HSA_OVERRIDE_GFX_VERSION
          value: "10.3.0"
        - name: LD_LIBRARY_PATH
          value: "/usr/lib/x86_64-linux-gnu"
        - name: TASK_ID
          value: "{task_id}"
        command: ["/bin/bash", "-c"]
        args:
        - |
          set -euo pipefail
          SCRATCH_DIR="/var/lib/ai-artifacts/scratch/${{TASK_ID}}"
          mkdir -p "$SCRATCH_DIR"
          MODEL_DIR="/opt/ai-models/diffusion"
          [ ! -d "$MODEL_DIR" ] && MODEL_DIR="/opt/ai-models/animatediff"
          MODEL_PATH="${{MODEL_DIR}}/toonyou_beta6.safetensors"
          [ ! -f "$MODEL_PATH" ] && MODEL_PATH="${{MODEL_DIR}}/realisticVisionV60B1.safetensors"
          MOTION_MODULE="${{MODEL_DIR}}/mm_sd15_v3.safetensors"
          SD_BIN="/opt/stable-diffusion.cpp/build/bin/sd-cli"
          STYLE="masterpiece, best quality, cartoon animation style, vibrant colors, 3D Pixar style, clean lines"
          NEG="photorealistic, real life photo, deformed, distorted, blurry, bad anatomy, bad quality, artifacts, watermark, ugly"

          PROMPTS=(
            "wide angle view, high-tech cartoon launchpad at sunset, cute small round retro blue robot with glowing cyan eyes standing next to sleek miniature silver rocket"
            "close-up portrait, cheerful young girl pilot, aviator goggles on forehead, bright yellow jacket, short brown bob hair, warm confident smile"
            "medium shot, cute small round retro blue robot with glowing cyan eyes pulling a glowing retro control lever, colorful energy sparks"
            "cinematic low angle, sleek miniature silver spaceship launching from platform, bright rainbow booster exhaust flame, billowing clouds of fluffy cartoon smoke"
            "tracking shot, sleek miniature silver rocket soaring upwards through golden clouds, beautiful orange sunset sky"
            "close-up, cute small round retro blue robot waving happily through glass spaceship dome window, joyful star-shaped glowing eyes"
            "cinematic wide view, sleek spaceship entering twilight space orbit above glowing cartoon planet Earth, sparkling stars"
            "wide cinematic view, glowing cartoon star constellation forming in deep starfield, celestial cosmic glow, title card background"
          )

          for s in {{1..8}}; do
            idx=$((s - 1))
            OUT_FILE="${{SCRATCH_DIR}}/shot_${{s}}_raw.webm"
            echo "Rendering Shot ${{s}}..."
            "$SD_BIN" -M vid_gen --model "$MODEL_PATH" --motion-module "$MOTION_MODULE" --diffusion-fa --mmap \\
              -p "${{STYLE}}, ${{PROMPTS[$idx]}}" -n "$NEG" -H 512 -W 512 --video-frames 16 --fps 8 --steps 14 --cfg-scale 7.0 \\
              --sampling-method euler_a --scheduler discrete -s $(( 42 + s * 17 )) -o "$OUT_FILE"
          done
          echo "All 8 shots rendered."
        volumeMounts:
        - name: host-usr-lib
          mountPath: /usr/lib/x86_64-linux-gnu
          readOnly: true
        - name: sd-cpp
          mountPath: /opt/stable-diffusion.cpp
          readOnly: true
        - name: models-storage
          mountPath: /opt/ai-models
          readOnly: true
        - name: artifacts-storage
          mountPath: /var/lib/ai-artifacts
      volumes:
      - name: host-usr-lib
        hostPath:
          path: /usr/lib/x86_64-linux-gnu
      - name: sd-cpp
        hostPath:
          path: /opt/stable-diffusion.cpp
      - name: models-storage
        persistentVolumeClaim:
          claimName: ai-models-pvc
      - name: artifacts-storage
        persistentVolumeClaim:
          claimName: ai-artifacts-pvc
"""
        p = subprocess.Popen('docker exec -i k3s-control-plane kubectl apply -f -', shell=True, stdin=subprocess.PIPE, text=True)
        p.communicate(input=job_manifest)
    else:
        print("  + Found active/existing sd-diffusion-job in cluster, waiting for it...")
    
    print("  + Waiting for AnimateDiff rendering to complete (up to 25 mins)...")
    run_kubectl("wait --for=condition=complete job/sd-diffusion-job --timeout=1800s")
    print("  + Video diffusion completed successfully!")


def submit_assembler_job(task_id: str):
    print(f"\n[Step 3/4] Triggering containerized FFmpeg assembly job in K3s...")
    run_kubectl("delete job media-assembler --ignore-not-found=true")

    job_manifest = f"""
apiVersion: batch/v1
kind: Job
metadata:
  name: media-assembler
spec:
  ttlSecondsAfterFinished: 600
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      nodeSelector:
        accelerator: amd-rocm
      containers:
      - name: ffmpeg-assembler
        image: jrottenberg/ffmpeg:6.1-alpine
        resources:
          limits:
            cpu: "3000m"
            memory: "1536Mi"
          requests:
            cpu: "1000m"
            memory: "512Mi"
        env:
        - name: TASK_ID
          value: "{task_id}"
        - name: OUTPUT_FILENAME
          value: "cartoon_30s_720p_30fps.mp4"
        command: ["/bin/sh", "-c"]
        args:
        - |
          set -eu
          SCRATCH="/var/lib/ai-artifacts/scratch/${{TASK_ID}}"
          OUT="/var/lib/ai-artifacts/outputs/${{TASK_ID}}"
          mkdir -p "$OUT"
          CONCAT="$SCRATCH/concat.txt"
          rm -f "$CONCAT"

          DURS="4.0 4.0 3.5 3.5 3.5 4.0 4.0 3.5"
          idx=1
          for DUR in $DURS; do
            RAW="$SCRATCH/shot_${{idx}}_raw.webm"
            PROC="$SCRATCH/shot_${{idx}}_720p.mp4"
            AUD="$SCRATCH/shot_${{idx}}_audio.wav"

            if [ -f "$AUD" ] && [ -s "$AUD" ]; then
              ffmpeg -y -stream_loop 2 -i "$RAW" -i "$AUD" \\
                -filter_complex "[0:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,fps=30,trim=duration=${{DUR}}[v];[1:a]atrim=duration=${{DUR}},apad=whole_dur=${{DUR}}[a]" \\
                -map "[v]" -map "[a]" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k "$PROC"
            else
              ffmpeg -y -stream_loop 2 -i "$RAW" -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \\
                -filter_complex "[0:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,fps=30,trim=duration=${{DUR}}[v];[1:a]atrim=duration=${{DUR}}[a]" \\
                -map "[v]" -map "[a]" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k "$PROC"
            fi
            echo "file '$PROC'" >> "$CONCAT"
            idx=$((idx + 1))
          done

          ffmpeg -y -f concat -safe 0 -i "$CONCAT" -c:v copy -c:a aac -b:a 192k "$OUT/${{OUTPUT_FILENAME}}"
          echo '{{"task_id": "${{TASK_ID}}", "status": "COMPLETED"}}' > "$OUT/metadata.json"
          echo "Assembly complete."
        volumeMounts:
        - name: dynamic-artifacts
          mountPath: /var/lib/ai-artifacts
      volumes:
      - name: dynamic-artifacts
        persistentVolumeClaim:
          claimName: ai-artifacts-pvc
"""
    p = subprocess.Popen('docker exec -i k3s-control-plane kubectl apply -f -', shell=True, stdin=subprocess.PIPE, text=True)
    p.communicate(input=job_manifest)

    print("  + Assembly job dispatched! Waiting for FFmpeg rendering to finish...")
    run_kubectl("wait --for=condition=complete job/media-assembler --timeout=180s")
    print("  + Media assembly completed successfully!")

def download_final_artifact(task_id: str):
    print(f"\n[Step 4/4] Downloading finalized master video from artifact-server ({ARTIFACT_URL})...")
    video_url = f"{ARTIFACT_URL}/outputs/{task_id}/cartoon_30s_720p_30fps.mp4"
    meta_url = f"{ARTIFACT_URL}/outputs/{task_id}/metadata.json"
    
    os.makedirs("artifacts", exist_ok=True)
    dest_video = f"artifacts/{task_id}_cartoon_30s_720p.mp4"
    dest_meta = f"artifacts/{task_id}_metadata.json"

    print(f"  + Fetching: {video_url}")
    urllib.request.urlretrieve(video_url, dest_video)
    urllib.request.urlretrieve(meta_url, dest_meta)

    size_mb = os.path.getsize(dest_video) / (1024 * 1024)
    print("=" * 60)
    print("=== CARTOON PRODUCTION COMPLETE ===")
    print(f"Saved Video: {dest_video} ({size_mb:.2f} MB)")
    print(f"Saved Metadata: {dest_meta}")
    print("=" * 60)

def main():
    task_id = sys.argv[1] if len(sys.argv) > 1 else f"task_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}"
    print("=" * 60)
    print(f"=== STARTING CARTOON STUDIO PIPELINE: {task_id} ===")
    print("=" * 60)

    try:
        synthesize_voices(task_id)
        submit_diffusion_job(task_id)
        submit_assembler_job(task_id)
        download_final_artifact(task_id)
    except Exception as e:
        print(f"\n[PIPELINE FAILED] {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
