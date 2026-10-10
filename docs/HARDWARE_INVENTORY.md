# Hardware Inventory & Configuration

This document serves as the verified source of truth for the edge AI node's physical hardware and low-level configuration. All data was verified directly from the bare-metal OS via `lscpu`, `dmidecode`, `lshw`, `free`, and live kernel inspection.

## 1. Core Compute (CPU & Memory)
*   **Processor (CPU):** AMD Ryzen 5 PRO 2600 Six-Core Processor
    *   **Architecture:** x86_64
    *   **Cores/Threads:** 6 Cores / 12 Threads
    *   **Base Clock:** 3.4 GHz (Min: 1.55 GHz)
    *   **Virtualization:** AMD-V Enabled
*   **System Memory (RAM):** 4 GB DDR4 (3.2 GiB usable after GPU/APU reserve)
    *   **Type:** DDR4 Synchronous Unbuffered (Unregistered)
    *   **Speed:** 2666 MT/s
    *   **Manufacturer:** A-DATA
    *   **Swap Configuration:** 16 GB Swap (`/swap.img`) configured to prevent OOM panics given the ultra-low 4GB physical footprint. (This severe RAM limitation validates the architectural decision to offload all non-inference components like LiteLLM, Prometheus, and OpenWebUI to the client machine).

## 2. Motherboard & Topography
*   **Manufacturer:** ASUSTeK COMPUTER INC.
*   **Model:** ROG STRIX B450-F GAMING II (Rev 1.xx)
*   **BIOS/Firmware:** SMBIOS 3.2.0
*   **PCIe Topology & Bifurcation:** Live kernel inspection (`lspci -tv` and `LnkSta`) reveals that both GPU slots connect directly to the Ryzen CPU Root Complex (`00:03.1` and `00:03.2`): GPU 0 negotiates at **PCIe 3.0 x8** (~7.88 GB/s) and GPU 1 negotiates at **PCIe 3.0 x4** (~3.94 GB/s). While neither routes through the B450 chipset, the lack of symmetrical x8/x8 bifurcation and hardware P2P DMA breaks Pipeline Parallelism, enforcing independent Replica and Multi-Modal workload separation.
*   **Thermal Monitoring:** ASUS WMI Super I/O driver (`asus-wmi-sensors`) installed via DKMS to bypass false 216°C readings that trigger CPU throttling down to 800MHz.

## 3. Storage
*   **Primary Disk:** GIGABYTE GP-GSTF (Solid State Drive)
*   **Capacity:** 120 GB (111.8 GiB usable)
*   **LVM Setup:** Extended to 100% capacity (`/dev/ubuntu-vg/ubuntu-lv`).
*   **Role:** Bare-metal OS boot drive, 16GB swap file, and local model `.gguf` cache (`/opt/ai-models`).

## 4. Accelerators (GPUs)
*   **GPU 0 (Primary):** AMD Radeon RX 6700 XT (Navi 22)
    *   **VRAM:** 12 GB GDDR6
    *   **Bus:** `pci@0000:0b:00.0`
    *   **Driver:** `amdgpu` (ROCm 7.x compatible via `HSA_OVERRIDE_GFX_VERSION=10.3.0`)
    *   **Role:** Dedicated to `llama-api-0` backend (Port 8082).
*   **GPU 1 (Secondary):** AMD Radeon RX 6700 XT (Navi 22)
    *   **VRAM:** 12 GB GDDR6
    *   **Bus:** `pci@0000:0e:00.0`
    *   **Driver:** `amdgpu` (ROCm 7.x compatible via `HSA_OVERRIDE_GFX_VERSION=10.3.0`)
    *   **Role:** Dedicated to `llama-api-1` backend (Port 8083).

## 5. Network, OS & Kernel Tuning
*   **Operating System:** Ubuntu 26.04 LTS (Bare-Metal, codename `resolute`)
*   **Kernel Flags (`/etc/default/grub`):** `GRUB_CMDLINE_LINUX_DEFAULT="quiet splash iommu=pt pcie_aspm=off"`
    *   `iommu=pt`: Enables IOMMU passthrough mode to minimize DMA overhead.
    *   `pcie_aspm=off`: Disables PCIe Active State Power Management to prevent link dropouts and ROCm driver crashes on the secondary PCIe 3.0 x4 bus.
*   **Networking:** Private mesh via Tailscale (`100.104.80.65`) and local Gigabit Ethernet (`enp3s0`).
*   **Host:** `ubuntu01`
*   **System Daemons:**
    *   `llama-api-0.service` (Port 8082, User: `llama-api`)
    *   `llama-api-1.service` (Port 8083, User: `llama-api`)
    *   `prometheus-node-exporter.service` (Port 9100, custom textfile collector at `/var/lib/prometheus/node-exporter`)
    *   `promtail.service` (Port 9080, User: `promtail`, log shipper to Loki)
    *   `tailscaled.service` (Mesh VPN)

---
*Note: Due to the extreme constraint of 4GB System RAM vs 24GB of total GPU VRAM, this node functions purely as a "dumb" accelerator appliance. It receives inference tasks over HTTP and returns answers, minimizing host OS memory allocations.*
