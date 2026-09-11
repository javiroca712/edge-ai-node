# Project State & Architecture

## 1. Project Overview
This project is an edge AI inference node designed to run large language models (LLMs) entirely locally on consumer-grade AMD GPUs. It provisions a high-performance, cost-effective private cloud capable of offline inference and integration into a broader DevSecOps automation pipeline.

## 2. Current Architecture
- **Hardware:** Asus ROG Strix B450-F Gaming II Motherboard (PCIe bottleneck: x8/x4 bifurcation), 2x AMD Radeon RX 6700 XT (12GB VRAM each), 128GB SATA SSD.
- **Operating System:** Bare-metal Ubuntu Server 26.04 LTS (shifted from a Proxmox hypervisor model to optimize for native PCIe device passthrough).
- **Compute Layer:** AMD ROCm stack leveraging the `HSA_OVERRIDE_GFX_VERSION=10.3.0` workaround to force support for the RDNA2 (gfx1030) architecture.
- **AI Engine (Current):** `llama.cpp` natively compiled with `GGML_HIPBLAS=ON` and patched to bypass driver-level memory allocation bugs (`max_blocks_per_sm`).
- **Parallelism Strategy:** Optimized for *Replica Parallelism* (Horizontal Scaling) running two independent 8B models (e.g., Llama 3.1 8B Instruct Q4_K_M) instead of *Pipeline Parallelism* due to the PCIe 3.0 x4 bandwidth limitation on the second GPU slot.
- **Frontend / Orchestration:** Docker-based Open WebUI running on a client machine, pointing to the server's API port.

## 3. Discovered State (Successfully Built & Tested)
- **OS Foundation:** Ubuntu installed, packages updated, and `lm-sensors` configured to bypass Asus hardware sensor mapping bugs.
- **ROCm Drivers:** The official AMD ROCm repository is registered and the core compute stack is installed natively via `apt`.
- **Permissions:** The `jroca` user has been added to the `video`, `render`, and `docker` groups, enabling non-root access to `/dev/dri` and `/dev/kfd`.
- **Inference Benchmark:** A Docker container (`ghcr.io/ggerganov/llama.cpp:server-rocm`) and a natively compiled `llama.cpp` binary have successfully executed and loaded the Meta-Llama-3.1-8B-Instruct-Q4_K_M model into VRAM, proving the ROCm layer works.

## 4. Known Issues & Blockers
- **Playwright/Browser Tooling:** While attempting to retrieve the Google Doc, the system browser driver failed to download due to a 404 error from the Microsoft CDN, indicating a transient infrastructure issue.
- **AMD Repo Sink Issues:** The AMD `apt` repositories occasionally return `404` or hash mismatches right after a release; the `rm -rf /var/lib/apt/lists/* && apt clean` workaround is required to force a sync.
- **Hardware Constraints:** The motherboard does not support x8/x8 PCIe lane splitting. The second slot is severely bottlenecked at x4 and disables the second M.2 NVMe slot.
- **Driver Bugs:** The consumer RX 6700 XT suffers from a `max_blocks_per_sm` memory limit bug in ROCm, which crashes pre-packaged Ollama binaries. This necessitated the native compilation of `llama.cpp` with C++ source patches.

## 5. Ollama Footprint (To Be Rewritten for vLLM)
To migrate this stack to vLLM, the following components contain Ollama-specific references that must be stripped:
1. **Open WebUI Configuration:** The Docker container currently orchestrating the frontend uses the environment variable `-e OLLAMA_BASE_URL="http://<YOUR_TAILSCALE_IP>:8082"`. This must be replaced with the OpenAI-compatible environment variable (e.g., `OPENAI_API_BASE_URL`) once vLLM is running.
2. **System Services:** Any `systemd` daemons running `ollama` or `llama.cpp` must be disabled and masked to free up TCP ports (11434, 8080, 8082) and VRAM.
3. **Execution Scripts:** The `docker/start_webui.sh` (extracted) contains the Ollama injection point that will be deprecated in the next phase.

## 6. vLLM Migration Plan & Next Steps
1. **Cleanup:** Terminate and `docker rm` any existing `llama.cpp` or Ollama containers holding VRAM.
2. **vLLM Compatibility Check:** Verify that vLLM's ROCm wheels support `gfx1030` out of the box, or prepare to compile vLLM from source using the same `HSA_OVERRIDE_GFX_VERSION` flags.
3. **Containerized vLLM Deployment:** Spin up the `vllm/vllm-openai` ROCm Docker image, mounting `/dev/kfd` and `/dev/dri`, pointing it to the `~/ai-models` directory.
4. **Update Frontend UI:** Relaunch the Open WebUI container, stripping the `OLLAMA_BASE_URL` and pointing its OpenAI connection strings to vLLM's standard port `8000`.
5. **Observability:** Set up the Prometheus `node_exporter` and `DCGM-Exporter` (or AMD equivalent) to monitor the VRAM usage of the new vLLM engine via Grafana.
