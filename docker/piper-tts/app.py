import os
import wave
import subprocess
import logging
from typing import Optional
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("piper-tts")

app = FastAPI(title="Edge Piper TTS Service", version="1.0.0")

MODEL_DIR = os.getenv("PIPER_MODEL_DIR", "/opt/ai-models/tts")
ARTIFACTS_DIR = os.getenv("ARTIFACTS_DIR", "/var/lib/ai-artifacts")

class SynthesizeRequest(BaseModel):
    task_id: str
    shot_id: int
    text: str
    voice: Optional[str] = "en_US-bryce-medium"
    speaker_id: Optional[int] = None

class OpenAISpeechRequest(BaseModel):
    input: str
    voice: Optional[str] = "en_US-bryce-medium"
    model: Optional[str] = "piper"
    response_format: Optional[str] = "wav"

def get_model_path(voice_name: str) -> str:
    # Look in MODEL_DIR
    model_path = os.path.join(MODEL_DIR, f"{voice_name}.onnx")
    if not os.path.exists(model_path):
        # Fallback check inside voices/ subfolder if present
        alt_path = os.path.join(MODEL_DIR, "voices", f"{voice_name}.onnx")
        if os.path.exists(alt_path):
            return alt_path
        raise HTTPException(
            status_code=404,
            detail=f"Voice model '{voice_name}' not found at {model_path}. Available voices: {os.listdir(MODEL_DIR) if os.path.exists(MODEL_DIR) else 'empty'}"
        )
    return model_path

def get_wav_duration(file_path: str) -> float:
    try:
        with wave.open(file_path, "r") as wf:
            frames = wf.getnframes()
            rate = wf.getframerate()
            return round(frames / float(rate), 2)
    except Exception as e:
        logger.warning(f"Could not calculate wav duration: {e}")
        return 0.0

@app.get("/health")
def health():
    return {"status": "ok", "service": "piper-tts", "model_dir": MODEL_DIR}

@app.get("/v1/voices")
def list_voices():
    if not os.path.exists(MODEL_DIR):
        return {"voices": []}
    files = os.listdir(MODEL_DIR)
    voices = [f[:-5] for f in files if f.endswith(".onnx")]
    return {"voices": voices}

@app.post("/v1/synthesize")
def synthesize(req: SynthesizeRequest):
    """
    Synthesizes speech and writes directly to scratch/<task_id>/shot_<shot_id>_audio.wav.
    Avoids client-side upload/download roundtrips.
    """
    if not req.text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty.")

    model_path = get_model_path(req.voice)
    task_dir = os.path.join(ARTIFACTS_DIR, "scratch", req.task_id)
    os.makedirs(task_dir, exist_ok=True)

    out_file = os.path.join(task_dir, f"shot_{req.shot_id}_audio.wav")

    cmd = ["piper", "--model", model_path, "--output_file", out_file]
    if req.speaker_id is not None:
        cmd.extend(["--speaker", str(req.speaker_id)])

    logger.info(f"Synthesizing shot {req.shot_id} for task {req.task_id} with voice {req.voice}...")
    try:
        proc = subprocess.run(
            cmd,
            input=req.text.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True
        )
    except subprocess.CalledProcessError as e:
        logger.error(f"Piper synthesis error: {e.stderr.decode('utf-8', errors='ignore')}")
        raise HTTPException(status_code=500, detail=f"Piper synthesis failed: {e.stderr.decode('utf-8', errors='ignore')}")

    duration = get_wav_duration(out_file)
    logger.info(f"Synthesized {out_file} successfully (Duration: {duration}s).")

    return {
        "status": "ok",
        "task_id": req.task_id,
        "shot_id": req.shot_id,
        "output_path": out_file,
        "duration_seconds": duration,
        "voice": req.voice
    }

@app.post("/v1/audio/speech")
def openai_speech(req: OpenAISpeechRequest):
    """
    OpenAI-compatible speech endpoint. Streams the WAV file in response body.
    """
    model_path = get_model_path(req.voice)
    cmd = ["piper", "--model", model_path, "--output_file", "-"]
    try:
        proc = subprocess.run(
            cmd,
            input=req.input.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True
        )
        return Response(content=proc.stdout, media_type="audio/wav")
    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=500, detail=f"Piper synthesis failed: {e.stderr.decode('utf-8', errors='ignore')}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8084)
