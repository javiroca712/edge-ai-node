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
