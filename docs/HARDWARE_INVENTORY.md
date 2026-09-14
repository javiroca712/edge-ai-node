# Hardware Inventory & Configuration

This document serves as the verified source of truth for the edge AI node's physical hardware and low-level configuration. All data was verified directly from the bare-metal OS via `lscpu`, `dmidecode`, `lshw`, and `free`.

## 1. Core Compute (CPU & Memory)
*   **Processor (CPU):** AMD Ryzen 5 PRO 2600 Six-Core Processor
    *   **Architecture:** x86_64
    *   **Cores/Threads:** 6 Cores / 12 Threads
    *   **Base Clock:** 3.4 GHz (Min: 1.55 GHz)
    *   **Virtualization:** AMD-V Enabled
*   **System Memory (RAM):** 4 GB DDR4
    *   **Type:** DDR4 Synchronous Unbuffered (Unregistered)
    *   **Speed:** 2666 MT/s
    *   **Manufacturer:** A-DATA
    *   **Swap Configuration:** 15 GB configured to prevent OOM panics given the ultra-low 4GB physical footprint. (This severe RAM limitation validates the architectural decision to offload all non-inference components like LiteLLM and OpenWebUI to the client machine).

## 2. Motherboard & Topography
*   **Manufacturer:** ASUSTeK COMPUTER INC.
*   **Model:** ROG STRIX B450-F GAMING II (Rev 1.xx)
*   **BIOS/Firmware:** SMBIOS 3.2.0
*   **PCIe Bottleneck:** The motherboard chipset does not support true x8/x8 bifurcation. The primary slot operates at x16 (or x8), but the secondary slot routes through the chipset at **PCIe 3.0 x4**. This physical reality breaks Peer-to-Peer (P2P) GPU memory transfers, enforcing the Replica Parallelism architecture.

## 3. Storage
*   **Primary Disk:** GIGABYTE GP-GSTF (Solid State Drive)
*   **Capacity:** 120 GB (111.8 GiB usable)
*   **Role:** Bare-metal OS boot drive, swap space, and local model `.gguf` cache.

## 4. Accelerators (GPUs)
*   **GPU 0 (Primary):** AMD Radeon RX 6700 XT (Navi 22)
    *   **VRAM:** 12 GB GDDR6
    *   **Bus:** `pci@0000:0b:00.0`
    *   **Driver:** `amdgpu`
    *   **Role:** Dedicated to `llama-api-0` backend (Port 8082).
*   **GPU 1 (Secondary):** AMD Radeon RX 6700 XT (Navi 22)
    *   **VRAM:** 12 GB GDDR6
    *   **Bus:** `pci@0000:0e:00.0`
    *   **Driver:** `amdgpu`
    *   **Role:** Dedicated to `llama-api-1` backend (Port 8083).

## 5. Network & OS
*   **Operating System:** Ubuntu 26.04 LTS (Bare-Metal)
*   **Kernel Overlay:** OverlayFS enabled (Docker storage).
*   **Networking:** Static LAN or Tailscale private mesh VPN (configured via `.env`)
*   **Host:** `ubuntu01`

---
*Note: Due to the extreme constraint of 4GB System RAM vs 24GB of total GPU VRAM, this node functions purely as a "dumb" accelerator appliance. It receives inference tasks over HTTP and returns answers, minimizing host OS memory allocations.*
