#!/usr/bin/env python3
"""
==============================================================================
Client Application: Cartoon Studio Pipeline Orchestrator
==============================================================================
Orchestrates end-to-end 30s cartoon production strictly via K3s containerized
services and dynamic Kubernetes batch jobs. Zero payloads run on the base OS.

Workflow:
  1. Script / Dialogue: Queries LiteLLM (localhost:4000) or llama-server (100.104.80.65:30083)
  2. Voice Synthesis: Calls containerized Piper TTS (100.104.80.65:30084/v1/synthesize)
  3. Video Generation: Dispatches containerized ROCm AnimateDiff Job to K3s
  4. Media Assembly: Dispatches containerized FFmpeg CPU Job (720p 30fps + audio mux)
  5. Download: Retrieves final MP4 & metadata via artifact-server (100.104.80.65:30085)
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

def load_env_file():
    """Load environment variables from project .env without external dependencies."""
    env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, val = line.split("=", 1)
                    os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))

load_env_file()

EDGE_NODE_HOST = os.getenv("EDGE_NODE_HOST", "100.104.80.65")
LITELLM_URL = os.getenv("LITELLM_URL", "http://localhost:4000/v1")
LLAMA_DIRECT_URL = f"http://{EDGE_NODE_HOST}:30083/v1"
PIPER_URL = f"http://{EDGE_NODE_HOST}:30084"
ARTIFACT_URL = f"http://{EDGE_NODE_HOST}:30085"

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

def load_and_template_manifest(manifest_filename: str, task_id: str) -> str:
    """Loads a Kubernetes job manifest template and substitutes runtime task_id."""
    manifest_path = os.path.join(os.path.dirname(__file__), "..", "k8s", manifest_filename)
    if not os.path.exists(manifest_path):
        raise FileNotFoundError(f"Manifest template not found at {manifest_path}")
    with open(manifest_path, "r", encoding="utf-8") as f:
        content = f.read()
    return content.replace("task_latest", task_id)


def submit_diffusion_job(task_id: str):
    print(f"\n[Step 2/4] Checking/Dispatching Video Diffusion Job to K3s cluster...")
    check = subprocess.run(
        'docker exec k3s-control-plane sh -c "kubectl get job sd-diffusion-job --no-headers"',
        shell=True, capture_output=True, text=True
    )

    if check.returncode != 0 or "sd-diffusion-job" not in check.stdout:
        print("  + Submitting new sd-diffusion-job from k8s/sd_diffusion_job_template.yaml...")
        job_manifest = load_and_template_manifest("sd_diffusion_job_template.yaml", task_id)
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

    print("  + Submitting media-assembler from k8s/media_assembler_job.yaml...")
    job_manifest = load_and_template_manifest("media_assembler_job.yaml", task_id)
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
