# Architectural Decisions & Challenges Log

This document summarizes the technical challenges encountered while building the edge AI inference node, the architectural pivots made, and the engineering rationale behind each decision.

## 1. Hypervisor Virtualization vs. Bare Metal
- **Initial Plan:** Build the cluster using Proxmox VE (managed via Terraform) to provide a fully virtualized, IaC-driven environment.
- **Pivot:** Migrated the AI compute node to **bare-metal Ubuntu Server (26.04 LTS)**.
- **Why:** The consumer-grade Asus ROG Strix B450-F Gaming II motherboard has rigid PCIe lane limitations. Injecting a hypervisor layer between the OS and the GPUs would add unnecessary overhead. By keeping the AI node on bare metal, we guarantee 100% direct I/O access to the PCIe bus (`/dev/kfd` and `/dev/dri`) for maximum tensor processing speed. Virtualization (Proxmox) was instead relegated to a secondary management/storage tier (building a hybrid cloud).

## 2. Multi-GPU Parallelism: Pipeline vs. Replica
- **Evaluated:** Splitting a large model (e.g., 70B parameter) across two 12GB RX 6700 XT GPUs (1x24GB Mode / Pipeline Parallelism).
- **Challenge:** The B450-F motherboard does not support x8/x8 PCIe bifurcation. While the primary slot runs at PCIe 3.0 x16, the secondary slot shares lanes with the M.2 NVMe drive and is severely bottlenecked at **PCIe 3.0 x4** (~3.9 GB/s). Handing off intermediate tensors across an x4 bus drops inference speeds to ~20 tokens per second.
- **Decision:** Optimize for **Replica Parallelism (2x12GB Mode)**. Each GPU loads and runs an independent 8B model locally, completely isolating the compute. A load balancer (LiteLLM) routes user prompts to whichever GPU is free. This eliminates cross-GPU PCIe chatter and yields a combined cluster throughput of ~160 tokens per second.

## 3. ROCm on Consumer RDNA2 Silicon
- **Challenge:** AMD's official ROCm framework strictly targets enterprise CDNA accelerators (Instinct MI-series) and actively blocks consumer RDNA2 cards like the RX 6700 XT (Navi 22 / `gfx1030`).
- **Workaround:** We successfully instructed the ROCm runtime to accept the unsupported silicon by forcing a global environment variable override: `export HSA_OVERRIDE_GFX_VERSION=10.3.0` in `/etc/profile.d/rocm-override.sh`.

## 4. Serving Engine: Ollama vs. Native `llama.cpp` Compilation
- **Initial Try:** Running pre-packaged, containerized wrappers like **Ollama** or generic Docker containers.
- **Challenge:** Unmodified AMD binaries hit a `max_blocks_per_sm > 0` driver-level memory allocation crash specific to `gfx1030` architectures during Flash Attention matrix computations (`tile_case<128, 128>`).
- **Decision:** Compile `llama.cpp` entirely from C++ source code with an explicit Flash Attention patch:
  ```cpp
  // ggml/src/ggml-cuda/fattn-common.cuh (line 1060)
  if (max_blocks_per_sm <= 0) { max_blocks_per_sm = 1; }
  ```
- **Why:** Building from source allowed the injection of explicit compiler flags (`-DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1030`) alongside this patch, bypassing the hardware driver abort and guaranteeing rock-solid stability.

## 5. The AMD Package Repository Sinkholes
- **Challenge:** Initial attempts to install ROCm using AMD's `repo.radeon.com` repository threw repeated `404 Not Found` and `File has unexpected size (hash mismatch)` errors due to CDN sync lags.
- **Decision:** Purged `/etc/apt/sources.list.d/rocm.list` and relied entirely on native Ubuntu 26.04 LTS (`resolute`) packages: `rocm-dev`, `hipcc`, `rocminfo`, `libhipblas-dev`, `libhipblas3`, and `librocm-smi-dev`. This guarantees package integrity and unifies security patching under standard Ubuntu updates.

## 6. Linux Hardware Sensor Mapping Bugs
- **Challenge:** Upon initial OS installation, the Linux `motd` reported the CPU temperature at 216.0°C due to floating pin readings on the Asus Super I/O chip. Linux `thermald` reacted by throttling the CPU down to 800MHz.
- **Decision:** Installed `lm-sensors` and compiled the out-of-tree DKMS driver `asus-wmi-sensors` (`https://github.com/electrified/asus-wmi-sensors.git`). This corrected the thermal telemetry, preventing false thermal throttling.

## 7. PCIe Active State Power Management (ASPM) & IOMMU
- **Challenge:** Under heavy sustained inference, the secondary RX 6700 XT on the PCIe 3.0 x4 bus would intermittently drop offline with `hipMemcpyAsync` timeouts or bus reset failures.
- **Decision:** Added `iommu=pt pcie_aspm=off` to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`. Disabling ASPM prevents PCIe link sleep transitions on consumer motherboards, while IOMMU passthrough minimizes translation latency.

## 8. Edge Node Observability: Push vs. Pull Telemetry
- **Challenge:** Standard Prometheus exporters cannot read AMD GPU power or Asus WMI motherboard sensors natively without heavy daemon overhead.
- **Decision:** Deployed `prometheus-node-exporter` with textfile collector directory `/var/lib/prometheus/node-exporter`. A lightweight shell script (`/usr/local/bin/gpu-metrics.sh`) polls `sysfs` (`hwmon`) and `turbostat` every 10 seconds via cron, performing atomic file writes. Promtail ships all systemd journals to Loki on the client machine.

## 9. Load Balancing Architecture: LiteLLM vs HAProxy
- **Decision:** Deployed **LiteLLM** on the local client machine instead of the edge server.
- **Why:** LiteLLM intercepts requests exactly like an OpenAI endpoint and tracks queue depths using a `least-busy` routing algorithm. Offloading this layer preserves 100% of the edge node's tight 4GB RAM for inference.

## 10. Multi-Modal Orchestration: Hybrid K3s Architecture
- **Challenge:** Scaling beyond text LLMs to video generation (e.g. Wan2.1 / LTX-Video) and other modalities requires dynamic model loading and unloading. A full Kubernetes control plane running locally on the edge node consumes ~1GB of RAM—eating 30% of the node's tight 3.2GB usable host memory and triggering severe swap thrashing.
- **Decision:** Adopted **Hybrid Kubernetes (Option B)**:
  - The **K3s Control Plane** runs in a lightweight Docker container on the client dev laptop, tainted `CriticalAddonsOnly=true:NoSchedule`.
  - The **Edge Node** runs only `k3s-agent` with `--kubelet-arg=fail-swap-on=false` to tolerate the 16GB swap file.
  - Custom node labels (`gpu.amd.com/slot0.bus=pcie-3.0-x16` and `gpu.amd.com/slot1.bus=pcie-3.0-x4`) inform scheduling so that dynamic heavy workloads (Video Generation) schedule on GPU 0 and resident text LLMs pin to GPU 1.
  - An automated Ansible rollback playbook (`ansible/rollback_k3s.yml`) provides instant recovery to native systemd daemons.

## 11. Pattern C: Dynamic GPU Scheduling + Dynamic Resource Allocation (DRA)
- **Challenge:** Hardcoding physical slot indices (`HIP_VISIBLE_DEVICES=0` vs `1`) and node hostnames works for a single identical node, but breaks immediately when scaling to a heterogeneous cluster where nodes may possess different numbers of GPUs, varying PCIe link widths (x16, x8, x4), or non-identical VRAM pools.
- **Architecture:** Implemented **Pattern C (Dynamic Resource Allocation with Unified AI Gateway)** across three tightly integrated tiers:
  1. **Tier 1 - Unified AI Gateway (LiteLLM Router):** Clients and consumer applications (Open WebUI, SDKs) query a single ingress gateway (`http://localhost:4000/v1`). The gateway dynamically routes and load-balances across active backend inference engines, shielding clients from cluster topology, node IPs, and card indices.
  2. **Tier 2 - Automated Hardware Introspection & Discovery:** Created `/usr/local/bin/discover_node_hardware.sh` to dynamically inspect GPUs, VRAM capacity, GFX architecture, and parent PCIe root port link widths directly via `sysfs`. Node labels (`accelerator=amd-rocm`, `gpu.amd.com/has-fastbus=true`, `gpu.amd.com/vram-gib=12`, `gpu.amd.com/arch=gfx1031`) are declaratively pushed to `/etc/rancher/k3s/config.yaml` via Ansible with zero manual configuration.
  3. **Tier 3 - Dynamic GPU Scheduling & On-Demand Lifecycle:** Deployed the official ROCm device plugin (`rocm/k8s-device-plugin`) as a DaemonSet targeting `accelerator: amd-rocm`, advertising allocatable `amd.com/gpu: 2`. Workloads declare standard `resources.limits: amd.com/gpu: 1` with soft node affinity (`preferredDuringSchedulingIgnoredDuringExecution` for `fastbus`). LLM servers scale on-demand between 0 and 1 replicas, instantly reclaiming and reallocating GPU VRAM across text and generative video batch jobs without oversubscription or crashes.

