"""
Unit tests for containerized Piper TTS FastAPI service.
Tests health endpoint, request models, and error handling.
Gracefully skips if running in an environment without FastAPI installed.
"""

import sys
import os
import unittest

# Add docker/piper-tts to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "docker", "piper-tts")))

try:
    from fastapi.testclient import TestClient
    from app import app, SynthesizeRequest, OpenAISpeechRequest
    HAS_FASTAPI = True
except ImportError:
    HAS_FASTAPI = False


class TestPiperTTSApi(unittest.TestCase):
    def setUp(self):
        if not HAS_FASTAPI:
            self.skipTest("fastapi/pydantic not installed in this Python environment")
        self.client = TestClient(app)

    def test_health_endpoint(self):
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["status"], "ok")
        self.assertEqual(data["service"], "piper-tts")

    def test_synthesize_request_validation(self):
        req = SynthesizeRequest(
            task_id="test_task_123",
            shot_id=1,
            text="Hello world from edge inference",
            voice="en_US-bryce-medium"
        )
        self.assertEqual(req.task_id, "test_task_123")
        self.assertEqual(req.shot_id, 1)
        self.assertEqual(req.voice, "en_US-bryce-medium")

    def test_synthesize_empty_text_rejection(self):
        response = self.client.post("/v1/synthesize", json={
            "task_id": "test_1",
            "shot_id": 1,
            "text": "   "
        })
        self.assertEqual(response.status_code, 400)
        self.assertIn("Text cannot be empty", response.json()["detail"])

    def test_openai_speech_request_defaults(self):
        req = OpenAISpeechRequest(input="Testing OpenAI speech compatibility")
        self.assertEqual(req.model, "piper")
        self.assertEqual(req.response_format, "wav")


if __name__ == "__main__":
    unittest.main()
