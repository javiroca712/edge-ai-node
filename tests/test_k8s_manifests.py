"""
Tests for Kubernetes YAML manifest syntax and structural integrity.
"""

import os
import glob
import unittest


def parse_yaml_docs(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    docs = content.split("\n---")
    return [d.strip() for d in docs if d.strip()]


class TestK8sManifests(unittest.TestCase):
    def test_k8s_manifest_files_exist(self):
        k8s_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "k8s"))
        manifests = glob.glob(os.path.join(k8s_dir, "*.yaml"))
        self.assertGreaterEqual(len(manifests), 4, f"Expected at least 4 manifests in {k8s_dir}")

    def test_core_manifests_have_apiversion_and_kind(self):
        k8s_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "k8s"))
        core_files = [
            "artifacts_pvc.yaml",
            "amd_gpu_device_plugin.yaml",
            "artifact_server.yaml",
            "piper_tts_deployment.yaml",
            "llama_server_dynamic.yaml",
            "media_assembler_job.yaml",
            "sd_diffusion_job_template.yaml"
        ]

        for fname in core_files:
            fpath = os.path.join(k8s_dir, fname)
            self.assertTrue(os.path.exists(fpath), f"Missing core manifest: {fname}")
            docs = parse_yaml_docs(fpath)
            for doc in docs:
                self.assertIn("apiVersion:", doc, f"Manifest {fname} missing apiVersion")
                self.assertIn("kind:", doc, f"Manifest {fname} missing kind")
                self.assertIn("metadata:", doc, f"Manifest {fname} missing metadata")

    def test_no_hostport_antipattern_in_dynamic_workloads(self):
        """Verify workloads do not use brittle hostPort bindings."""
        k8s_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "k8s"))
        dynamic_workloads = [
            "llama_server_dynamic.yaml",
            "piper_tts_deployment.yaml",
            "artifact_server.yaml"
        ]
        for fname in dynamic_workloads:
            fpath = os.path.join(k8s_dir, fname)
            with open(fpath, "r", encoding="utf-8") as f:
                content = f.read()
            self.assertNotIn("hostPort:", content, f"Antipattern found: {fname} contains hostPort")

    def test_nodeport_services_in_valid_range(self):
        """Verify services define standard Kubernetes NodePorts (30000-32767)."""
        import re
        k8s_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "k8s"))
        service_files = [
            "llama_server_dynamic.yaml",
            "piper_tts_deployment.yaml",
            "artifact_server.yaml"
        ]
        nodeport_regex = re.compile(r"nodePort:\s*(\d+)")
        for fname in service_files:
            fpath = os.path.join(k8s_dir, fname)
            with open(fpath, "r", encoding="utf-8") as f:
                content = f.read()
            self.assertIn("type: NodePort", content, f"Expected {fname} to declare type: NodePort")
            matches = nodeport_regex.findall(content)
            self.assertTrue(matches, f"Expected nodePort in {fname}")
            for port_str in matches:
                port = int(port_str)
                self.assertTrue(30000 <= port <= 32767, f"NodePort {port} in {fname} out of range [30000, 32767]")


if __name__ == "__main__":
    unittest.main()
