# Architectural Decisions & Challenges Log

This document summarizes the technical challenges encountered while building the edge AI inference node, the architectural pivots made, and the engineering rationale behind each decision.

## 1. Hypervisor Virtualization vs. Bare Metal
- **Initial Plan:** Build the cluster using Proxmox VE (managed via Terraform) to provide a fully virtualized, IaC-driven environment.
- **Pivot:** Migrated the AI compute node to **bare-metal Ubuntu Server (26.04 LTS)**.
- **Why:** The consumer-grade Asus ROG Strix B450-F Gaming II motherboard has rigid PCIe lane limitations. Injecting a hypervisor layer between the OS and the GPUs would add unnecessary overhead. By keeping the AI node on bare metal, we guarantee 100% direct I/O access to the PCIe bus (`/dev/kfd` and `/dev/dri`) for maximum tensor processing speed. Virtualization (Proxmox) was instead relegated to a secondary management/storage tier (building a hybrid cloud).

## 2. Multi-GPU Parallelism: Pipeline vs. Replica
- **Evaluated:** Splitting a large model (e.g., 70B parameter) across two 12GB RX 6700 XT GPUs (1x24GB Mode / Pipeline Parallelism).
- **Challenge:** The B450-F motherboard does not support x8/x8 PCIe bifurcation. While the primary slot runs at PCIe 3.0 x16, the secondary slot shares lanes with the M.2 NVMe drive and is severely bottlenecked at **PCIe 3.0 x4** (~3.9 GB/s). Handing off intermediate tensors across an x4 bus drops inference speeds to ~20 tokens per second.
- **Decision:** Optimize for **Replica Parallelism (2x12GB Mode)**. Each GPU loads and runs an independent 8B model locally, completely isolating the compute. A load balancer (like LiteLLM or Kubernetes Ingress) routes user prompts to whichever GPU is free. This eliminates cross-GPU PCIe chatter and yields a combined cluster throughput of ~140 tokens per second.

## 3. ROCm on Consumer RDNA2 Silicon
- **Challenge:** AMD's official ROCm (Radeon Open Compute) framework strictly targets enterprise CDNA accelerators (Instinct MI-series). It actively blocks consumer RDNA2 cards like the RX 6700 XT.
- **Workaround:** We successfully tricked the ROCm runtime into accepting the unsupported silicon by forcing a global environment variable override: `export HSA_OVERRIDE_GFX_VERSION=10.3.0`.

## 4. Serving Engine: Ollama vs. Native `llama.cpp` Compilation
- **Initial Try:** Running pre-packaged, containerized wrappers like **Ollama** for model serving.
- **Challenge:** The generic, pre-compiled AMD binaries provided by Ollama do not account for edge-case consumer silicon bugs. When pushed with high context windows, the unmodified drivers hit a `max_blocks_per_sm > 0` driver-level memory allocation crash specific to `gfx1030` architectures.
- **Decision:** Compile `llama.cpp` entirely from C++ source code.
- **Why:** Building from source allowed the injection of explicit compiler flags (`-DAMDGPU_TARGETS=gfx1030`) and manual C++ patches to the Flash Attention kernel (`fattn-common.cuh`), bypassing the hardware driver crashes and guaranteeing enterprise-grade stability.

## 5. The AMD Package Repository Sinkholes
- **Challenge:** Initial attempts to install the ROCm stack using AMD's `amdgpu-install` wrapper script threw repeated `404 Not Found` and `File has unexpected size (hash mismatch)` errors.
- **Why:** AMD's global CDN frequently experiences sync lags between repository manifests and edge cache binaries immediately following a release cycle.
- **Decision:** Abandoned the brittle wrapper script. Manually imported the GPG signing keys, directly mapped the native `apt` repositories (pointing securely to the `noble` branch), and executed forced cache purges (`rm -rf /var/lib/apt/lists/*`) to rotate the CDN edge nodes.

## 6. Linux Hardware Sensor Mapping Bugs
- **Challenge:** Upon initial OS installation, the Linux `motd` reported the CPU temperature at 216.0°C.
- **Why:** Asus motherboards using the ITE Super I/O chip frequently map floating hardware pins to generic Linux sensor hooks, resulting in garbage data. If left unresolved, the Linux thermal daemon (`thermald`) would panic and forcefully throttle the CPU to 800MHz to "save" the hardware during heavy inference.
- **Decision:** Deployed `lm-sensors` and executed a forced `sensors-detect` hardware probe to recalibrate the driver mappings, ensuring system logic remains tied to true thermal reality.
