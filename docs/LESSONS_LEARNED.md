# Lessons Learned & Technical Insights

This document captures the key engineering insights, gotchas, and phenomena discovered while building the edge AI inference node.

## 1. Continuous Batching is a Multiplier
**Context:** When benchmarking a single `llama.cpp` request on a single RX 6700 XT, we observed a steady ~50-53 tokens/sec. 
**Discovery:** When we fired a concurrent stress test (4 massive requests simultaneously) routed via LiteLLM, we assumed throughput would split and drop. Instead, due to `llama.cpp`'s continuous batching capabilities, the GPU processed two concurrent text generation streams at ~40 t/s each. 
**Insight:** By serving multiple streams at once, the GPU leverages its highly parallel architecture much better. The aggregate throughput of a single GPU jumped from ~50 t/s to ~80 t/s. Across two GPUs (Replica Parallelism), the cluster achieved a massive combined throughput of ~160 tokens per second.

## 2. The Danger of Ephemeral Container Storage
**Context:** The initial PLG (Prometheus, Loki, Grafana) stack was spun up rapidly on the host machine using an un-optimized `docker-compose.yml`.
**Discovery:** The `grafana/grafana` image does not enforce host-level volume mapping. When we executed `docker compose down` to migrate the stack into the codebase, Docker permanently destroyed the ephemeral writable layer of the Grafana container. All customized dashboards were instantly vaporized.
**Insight:** Never trust implicit or anonymous container volumes for production state. We rewrote the Docker Compose configuration to explicitly map `grafana_data:/var/lib/grafana` and fully embraced "Dashboards as Code" using Grafana's Auto-Provisioning API.

## 3. API Gateways Demand API Keys (Even if the Backend Doesn't)
**Context:** We deployed `LiteLLM` to act as an intelligent load balancer sitting in front of our two `llama.cpp` bare-metal endpoints. `llama.cpp` was run natively without authentication.
**Discovery:** When we initially load tested LiteLLM, all requests were instantly dropped with an HTTP 500 AuthenticationError. LiteLLM strictly enforces the OpenAI Python Client schema under the hood, which actively throws an exception if the `OPENAI_API_KEY` is null or empty.
**Insight:** When building AI gateways, always pass a dummy `api_key: "sk-1234"` to upstream clients to satisfy schema validators, even if the terminating endpoint is an unauthenticated local process.

## 4. Hardware PCIe Topology Matters More Than Raw Compute
**Context:** We attempted Pipeline Parallelism (splitting a single model across both GPUs).
**Discovery:** Despite having two powerful RX 6700 XT cards, ROCm violently crashed with `hipMemcpyAsync` errors. The Asus B450 motherboard topology forces the second PCIe slot to run at x4 speeds, physically preventing the massive Peer-to-Peer (P2P) memory transfers required for layer-splitting. 
**Insight:** Software architecture must map to physical reality. We abandoned Pipeline Parallelism and pivoted to Replica Parallelism, letting LiteLLM handle the clustering at the HTTP layer, bypassing the PCIe bottlenecks entirely.

## 5. The RDNA2 Flash Attention Driver Trap (`max_blocks_per_sm`)
**Context:** Compiling `llama.cpp` with `-DAMDGPU_TARGETS=gfx1030` and launching prompts with larger context windows.
**Discovery:** `llama-server` crashed with an immediate abort: `GGML_ASSERT(max_blocks_per_sm > 0) failed` in `fattn-common.cuh`. Because Navi 22 has fewer Vector General-Purpose Registers (VGPRs) per Compute Unit than enterprise cards, the occupancy calculator returned 0 active blocks for the standard 128x128 tile kernel.
**Insight:** Always patch `if (max_blocks_per_sm <= 0) { max_blocks_per_sm = 1; }` before compiling, or constrain micro-batch sizes (`-ub 64 -b 64`) to force smaller tile allocations on consumer AMD hardware.

## 6. PCIe Active State Power Management (ASPM) on Secondary Slots
**Context:** Heavy inference runs would intermittently hang or disconnect the secondary GPU on PCIe 3.0 x4.
**Discovery:** Consumer motherboards route secondary slots through the chipset, where aggressive OS-level ASPM attempts power-saving sleep transitions during transient memory-transfer pauses, corrupting the ROCm ring buffer.
**Insight:** Always boot bare-metal GPU nodes with `pcie_aspm=off iommu=pt` in GRUB.

## 7. Forensic Auditing for Infrastructure-as-Code (IaC)
**Context:** Transitioning a manually tuned server to automated Ansible playbooks after months of debugging.
**Discovery:** Imperative scripts left in the repo missed critical tweaks: DKMS drivers, swap files, crontab metric pollers, and custom system accounts.
**Insight:** Never write IaC solely from memory or old notes. Always perform live host forensic auditing (`apt-mark showmanual`, `/var/log/apt/history.log`, `systemctl list-units`, and `.bash_history`) to capture all "Dark Matter" changes.

## 8. The 4GB Host RAM & Python 3.14 Trap: Why Native C++ is Mandatory
**Context:** Attempting to deploy video and image generation pipelines (AnimateDiff, Stable Diffusion) on a node with only 4GB host RAM and Ubuntu 26.04 (Python 3.14).
**Discovery:** Standard Python-based frameworks (Diffusers, ComfyUI) fail catastrophically in this environment for two reasons: (1) PyTorch lacks prebuilt ROCm wheels for Python 3.14, and Ubuntu's packaged `python3-torch-rocm` was compiled for enterprise CDNA (`gfx908`/`gfx90a`), instantly segfaulting on consumer RDNA2 (`gfx1030`); (2) ComfyUI and PyTorch allocate large multi-gigabyte staging buffers in host RAM before copying to VRAM, instantly triggering brutal swap thrashing on SATA SSDs and kernel OOM kills.
**Insight:** By compiling native C++ engines (`stable-diffusion.cpp` / `sd-cli`) with HIPBLAS, weights are directly `mmap`'d from disk into VRAM with zero host-RAM buffer duplication. The entire 16-frame AnimateDiff pipeline ran with only 1.5GB of physical host RAM consumed, completely avoiding SATA SSD swap thrashing.

## 9. Dual-GPU Asymmetric Role Specialization
**Context:** Deploying heterogeneous workloads (Text LLMs and Generative Video) across bifurcated PCIe slots (x8 vs x4).
**Discovery:** Empirical benchmarking proved that LLM autoregressive token decoding is 100% bandwidth-invariant between x8 and x4 (~53 t/s on both). However, heavy dynamic payloads like video generation frequently load and initialize gigabytes of multi-modal tensors (U-Net + Motion Modules + VAE).
**Insight:** Pin steady-state resident LLMs (`llama-server`) to GPU 1 (PCIe 3.0 x4) and dedicate GPU 0 (PCIe 3.0 x8) to dynamic burst payloads (Video Generation, Vision-Language models). This ensures the resident text API remains 100% available and responsive while dynamic payloads maximize the higher bandwidth PCIe bus.

## 10. The Sysfs Upstream Root Port Traversal Trap
**Context:** Discovering actual PCIe bus link widths dynamically across heterogeneous motherboards.
**Discovery:** Inspecting the GPU device directly via `lspci -vvv -s <BUS>` or `/sys/bus/pci/devices/<BUS>/current_link_width` always reports the card's maximum internal capability (`Width x16`). It completely ignores that the motherboard's physical slot or chipset may only negotiate x8 or x4 bandwidth.
**Insight:** Accurate bandwidth detection requires traversing the sysfs tree to the CPU root complex upstream parent port (`/sys/devices/pci.../0000:00:03.X/current_link_width`). This reveals the true negotiated electrical lane width (e.g., x8 vs x4) and enables intelligent Kubernetes scheduling.

## 11. Kubernetes Rolling Updates with `hostPort` and GPU Limits
**Context:** Updating containerized inference servers bound to host ports (`hostPort: 8083`) and requesting dedicated GPU limits (`amd.com/gpu: 1`).
**Discovery:** Standard Kubernetes deployments default to `RollingUpdate` with `maxSurge: 25%`. The controller attempts to launch the replacement pod before destroying the old pod. On single-node edge setups, this immediately fails with a port binding collision (`node didn't have free ports for the requested pod ports`) or GPU resource exhaustion.
**Insight:** Deployments utilizing host ports or physical hardware accelerators should declare `strategy.type: Recreate`. This guarantees the old pod terminates and frees both the port and the GPU device before the new pod is scheduled.

## 12. Model Cold Load vs Kubernetes Startup Probes
**Context:** Deploying large quantized models (4.9GB GGUF) from SATA SSD into VRAM on a low-RAM host.
**Discovery:** While loading weights, `llama-server` returns HTTP 503 (`{"error":"Loading model"}`). Standard `livenessProbe` with short initial delay treats 503 responses as container failure and restarts the container mid-load, entering an endless crash loop.
**Insight:** Decouple initialization from liveness by implementing a dedicated `startupProbe` with high failure thresholds (`failureThreshold: 40`, `periodSeconds: 5`). This grants up to 200 seconds of cold-load buffer for slow SATA SSD storage, while allowing `livenessProbe` and `readinessProbe` to run with tight intervals once the model is active.


