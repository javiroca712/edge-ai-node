"""
Unit tests for Cartoon Studio pipeline orchestrator.
Verifies shot timeline geometry, manifest templating, and prompt completeness.
"""

import os
import sys
import unittest

# Add scripts to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "scripts")))

from cartoon_studio import SHOTS, load_and_template_manifest


class TestCartoonStudio(unittest.TestCase):
    def test_shot_count_and_duration(self):
        self.assertEqual(len(SHOTS), 8, "Expected exactly 8 cartoon shots")
        total_duration = sum(shot["duration"] for shot in SHOTS)
        self.assertEqual(total_duration, 30.0, f"Expected total 30.0 seconds, got {total_duration}")

    def test_shot_fields_integrity(self):
        for shot in SHOTS:
            self.assertIn("id", shot)
            self.assertIn("prompt", shot)
            self.assertGreater(len(shot["prompt"]), 10)
            self.assertIn("duration", shot)
            self.assertGreater(shot["duration"], 0)
            self.assertIn("dialogue", shot)

    def test_manifest_templating_diffusion(self):
        task_id = "task_unit_test_999"
        rendered = load_and_template_manifest("sd_diffusion_job_template.yaml", task_id)
        self.assertIn(task_id, rendered)
        self.assertNotIn("task_latest", rendered)
        self.assertIn("sd-diffusion-job", rendered)

    def test_manifest_templating_assembler(self):
        task_id = "task_unit_test_999"
        rendered = load_and_template_manifest("media_assembler_job.yaml", task_id)
        self.assertIn(task_id, rendered)
        self.assertNotIn("task_latest", rendered)
        self.assertIn("media-assembler", rendered)


if __name__ == "__main__":
    unittest.main()
