# 🚀 Edge AI Node: Bare-Metal Multi-GPU Inference Cluster

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI/CD: GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF.svg)](.github/workflows/)
[![IaC: Ansible & Terraform](https://img.shields.io/badge/IaC-Ansible%20%7C%20Terraform-663399.svg)](terraform/)
[![Orchestration: K3s Edge](https://img.shields.io/badge/Orchestration-K3s%20Cluster-FFC61C.svg)](k8s/)
[![ROCm: 6.x (gfx1030)](https://img.shields.io/badge/ROCm-gfx1030%20(RDNA2)-red.svg)](docs/ARCHITECTURAL_DECISIONS.md)
[![Gateway: LiteLLM](https://img.shields.io/badge/Gateway-LiteLLM%20Router-purple.svg)](docker/litellm/)
[![Observability: PLG Stack](https://img.shields.io/badge/Observability-Prometheus%20%7C%20Grafana-green.svg)](docker/plg-stack/)

A high-performance, cost-effective private AI inference cluster running large language models (LLMs) locally on consumer-grade AMD GPUs. Designed for offline inference, continuous batching, and integration into autonomous agent workflows (e.g., CrewAI, AutoGen, OpenClaw).

---

## 1. Project Overview & Architectural Pivot

* **The Pivot from Proxmox to Bare-Metal Ubuntu:** The initial architecture explored virtualizing the cluster on Proxmox VE. However, consumer-grade motherboards (such as the Asus ROG Strix B450-F) impose severe PCIe lane bifurcations (x16 / x4). Introducing a hypervisor abstraction layer between the OS and the GPUs degraded DMA throughput and introduced kernel panics during multi-GPU handshakes.
* **Bare-Metal Decision:** The inference node runs on **bare-metal Ubuntu Server (26.04 LTS)** to ensure direct, uninhibited I/O access to the PCIe bus (`/dev/kfd` and `/dev/dri`). This eliminates virtualization latency and guarantees maximum memory bandwidth for tensor compute.

---

## 2. System Architecture

* **Hardware Foundation:**
  * **Motherboard:** Asus ROG Strix B450-F Gaming II (Primary PCIe 3.0 x16, Secondary PCIe 3.0 x4 via chipset).
  * **Compute Accelerators:** 2x AMD Radeon RX 6700 XT (12GB GDDR6 VRAM each, Navi 22 / gfx1030 silicon, 24GB VRAM total).
  * **CPU & Memory:** AMD Ryzen 5 PRO 2600 (6C/12T) with **4GB DDR4 System RAM** and 15GB Swap.
  * *Design note:* Due to the tight 4GB physical host RAM, the edge node acts strictly as a dedicated inference appliance. All orchestration and reverse-proxy services are offloaded to the client machine.
* **Compute Stack & ROCm Workarounds:**
  * AMD ROCm stack configured with `export HSA_OVERRIDE_GFX_VERSION=10.3.0` to force official compute support on consumer RDNA2 silicon.
  * Natively compiled `llama.cpp` with `GGML_HIPBLAS=ON` and custom Flash Attention kernel adjustments to prevent driver-level `max_blocks_per_sm` allocation crashes.
* **Parallelism Strategy (Replica vs. Pipeline):**
  * Rather than splitting a single model across GPUs (Pipeline Parallelism, which stalls on the secondary PCIe 3.0 x4 link), the cluster runs **Replica Parallelism**.
  * Two independent instances of Meta-Llama-3.1-8B-Instruct run concurrently: GPU 0 on port `8082` and GPU 1 on port `8083`.
* **Client Gateway & Routing:**
  * **LiteLLM Router** running locally via Docker Desktop (`localhost:4000`), load-balancing OpenAI API requests across both edge GPUs using a dynamic `least-busy` algorithm.
  * **Open WebUI** running on `localhost:3000` for conversational interaction.
* **Observability (Dashboards-as-Code):**
  * A full PLG stack (Prometheus, Loki, Grafana) deployed via Docker Compose (`localhost:3001`).
  * Grafana dashboards and Prometheus data sources are auto-provisioned declaratively from Git repository configs.

---

## 3. Architecture Diagram

```mermaid
flowchart TD
    subgraph Client ["Client Machine (Local Docker Desktop)"]
        direction TB
        UI["Open WebUI (Port 3000)"]
        Agents["Local AI Agents (CrewAI/AutoGen)"]
        
        subgraph Docker ["Docker Network"]
            LiteLLM["LiteLLM Router (Port 4000)"]
            
            subgraph PLG ["PLG Observability Stack"]
                Grafana["Grafana (Port 3001)"]
                Prometheus["Prometheus (Port 9090)"]
                Loki["Loki"]
            end
        end
    end

    subgraph Edge ["Edge AI Node (Ubuntu Server Bare-Metal)"]
        direction TB
        
        subgraph SystemD ["SystemD Daemons"]
            Llama0["llama-api-0 (Port 8082)"]
            Llama1["llama-api-1 (Port 8083)"]
        end
        
        subgraph Compute ["Compute Layer"]
            ROCm0["ROCm (gfx1030)"]
            ROCm1["ROCm (gfx1030)"]
        end
        
        subgraph Hardware ["Hardware Layer"]
            GPU0["GPU 0 (RX 6700 XT - x16)"]
            GPU1["GPU 1 (RX 6700 XT - x4)"]
        end
    end

    %% Routing
    UI -->|OpenAI API| LiteLLM
    Agents -->|OpenAI API| LiteLLM
    LiteLLM -->|Load Balances HTTP| Llama0
    LiteLLM -->|Load Balances HTTP| Llama1

    %% Compute Stack
    Llama0 --> Compute
    Llama1 --> Compute
    ROCm0 --> GPU0
    ROCm1 --> GPU1

    %% Observability
    Grafana -->|Queries| Prometheus
    Grafana -->|Queries| Loki
    Prometheus -.->|Scrapes /metrics| Llama0
    Prometheus -.->|Scrapes /metrics| Llama1
```

---

## 4. Repository Structure

```text
├── .github/workflows/                    # Automated CI/CD Pipelines
│   ├── lint-and-validate.yml             # yamllint, shellcheck, kubeconform, ruff & unit tests
│   ├── terraform-validate.yml            # terraform fmt & validation
│   └── docker-publish.yml                # OCI image build & push to GitHub Container Registry (GHCR)
├── ansible/                              # Host OS Lifecycle & Provisioning (Bare Metal)
│   ├── inventory.yml                     # Parameterized inventory with environment lookup
│   ├── inventory.example.yml             # Template inventory
│   ├── deploy_edge_node.yml              # Master bare-metal node playbook
│   └── roles/
│       ├── os_tuning/                    # GRUB flags (pcie_aspm=off), 16GB swap, LVM, asus-wmi-sensors DKMS
│       ├── amd_rocm/                     # Native Ubuntu 26.04 ROCm 7.x stack & system accounts
│       ├── k3s_agent/                    # Dynamic sysfs hardware discovery & k3s-agent daemon
│       ├── llamacpp_build/               # Source compilation, Flash Attention patch, GGUF models
│       ├── stable_diffusion_cpp/         # AnimateDiff v3 + ToonYou model compilation
│       └── observability/                # Node exporter textfile collector & Promtail
├── docker/                               # Containerized Tools & Runtimes (Dev Laptop)
│   ├── k3s-control-plane/                # K3s server container (laptop:6443) with kubeconfig output
│   ├── ansible-runner/                   # Zero-dependency containerized Ansible runner
│   ├── terraform-runner/                 # Zero-dependency containerized Terraform runner
│   ├── litellm/                          # LiteLLM router (least-busy load balancer)
│   ├── plg-stack/                        # Prometheus, Loki, Grafana observability stack
│   ├── piper-tts/                        # Standalone Piper neural voice synthesis microservice
│   ├── llama-server/                     # ROCm gfx1030 standalone llama.cpp server container
│   └── sd-diffusion/                     # ROCm gfx1030 AnimateDiff video generation container
├── k8s/                                  # Kubernetes Manifests & Storage Bindings
│   ├── kustomization.yaml                # Declarative Kustomize resource index
│   ├── artifacts_pvc.yaml                # ai-models (RO) and ai-artifacts (RWX) PV & PVCs
│   ├── amd_gpu_device_plugin.yaml        # Official ROCm k8s-device-plugin DaemonSet
│   ├── artifact_server.yaml              # Nginx static video asset HTTP streaming server
│   ├── piper_tts_deployment.yaml         # Containerized Piper TTS FastAPI service
│   ├── llama_server_dynamic.yaml         # Dynamic GPU LLM inference server
│   ├── media_assembler_job.yaml          # FFmpeg 720p 30fps containerized assembly job
│   └── sd_diffusion_job_template.yaml    # AnimateDiff GPU video generation batch job
├── terraform/                            # In-Cluster Infrastructure as Code
│   ├── providers.tf                      # Kubernetes & Helm providers
│   ├── main.tf                           # Namespaces, PVCs, Device Plugin, Deployments & Services
│   ├── variables.tf                      # Cluster configuration variables
│   ├── outputs.tf                        # Service HTTP endpoints
│   └── terraform.tfvars.example          # Sample variables file
├── docs/
│   ├── ARCHITECTURAL_DECISIONS.md        # Detailed engineering logs, IaC boundaries & pivot rationale
│   ├── HARDWARE_INVENTORY.md             # Verified bare-metal hardware telemetry
│   └── LESSONS_LEARNED.md                # Benchmarks, container gotchas & technical insights
├── scripts/
│   ├── cartoon_studio.py                 # Pure Python end-to-end 30s cartoon pipeline orchestrator
│   ├── deploy_k8s_workloads.ps1          # Kubernetes workload management helper
│   ├── run_ansible.ps1                   # Docker-based Ansible execution helper
│   ├── run_terraform.ps1                 # Docker-based Terraform execution helper
│   └── discover_node_hardware.sh         # Dynamic PCIe link & VRAM sysfs discovery script
├── tests/
│   ├── test_cartoon_studio.py            # Unit tests for timeline geometry & templating
│   ├── test_k8s_manifests.py             # Schema & syntax tests for all K8s manifests
│   ├── test_piper_tts_api.py             # FastAPI unit tests for TTS service
│   ├── benchmark_live_gpus.ps1           # Live PCIe asymmetry stress test
│   └── test_k8s_llama.ps1                # OpenAI API latency benchmark
├── .env.example                          # Environment variable configuration template
├── .gitignore                            # Excludes build artifacts, models, .env, secrets & tfstate
└── LICENSE                               # MIT License
```

---

## 5. In-Depth Engineering Documentation

For comprehensive technical post-mortems and engineering logs, refer to the documentation in [`docs/`](docs/):

* [**Architectural Decisions Log**](docs/ARCHITECTURAL_DECISIONS.md) — Rationale for bare-metal Ubuntu vs. Proxmox, Pipeline vs. Replica parallelism, resolving ROCm kernel deadlocks, and AMD repo CDN sinkholes.
* [**Hardware Inventory & Telemetry**](docs/HARDWARE_INVENTORY.md) — CPU/RAM constraints, Asus B450 PCIe topology, and physical GPU bus addresses.
* [**Lessons Learned & Benchmarks**](docs/LESSONS_LEARNED.md) — Continuous batching throughput dynamics, Grafana volume persistence, and AI gateway API key schemas.

---

## 6. Quickstart & Local Setup

### Step 1: Provision the Bare-Metal Ubuntu Node
From your control machine with Ansible installed:
```bash
# 1. Update the inventory file with your node's IP address
nano ansible/inventory.yml

# 2. Run the Ansible playbook to provision the OS, install ROCm, build llama.cpp, and start the replica services
ansible-playbook -i ansible/inventory.yml ansible/deploy_edge_node.yml -K
```

### Step 2: Configure and Launch Client Stack
On your client workstation (Windows / macOS / Linux with Docker):

1. Copy the environment configuration template:
   ```bash
   cp .env.example .env
   ```
2. Open `.env` and set `EDGE_NODE_HOST` to your node's IP address (e.g. Tailscale or Local LAN IP):
   ```env
   EDGE_NODE_HOST=100.x.y.z
   GRAFANA_ADMIN_PASSWORD=admin
   ```
3. Start the LiteLLM load balancer:
   ```bash
   cd docker/litellm && docker compose up -d && cd ../..
   ```
4. Start the Prometheus & Grafana observability stack:
   ```bash
   cd docker/plg-stack && docker compose up -d && cd ../..
   ```

### Step 3: Run the Concurrent Load Test
Verify multi-GPU load balancing and continuous batching by firing concurrent long-context requests:
```powershell
powershell -ExecutionPolicy Bypass -File tests/load_test.ps1
```
Open **Grafana** at `http://localhost:3001` (user: `admin`) to observe real-time GPU compute throughput and prediction queues.

---

## 7. Discovered Benchmarks

* **Single-Stream Baseline:** ~50–53 tokens/sec on a single RX 6700 XT running `Meta-Llama-3.1-8B-Instruct-Q4_K_M`.
* **Continuous Batching Multiplier:** Under 4 concurrent heavy prompt streams routed through LiteLLM, `llama.cpp`'s continuous batching dynamically coalesced execution, yielding ~40 t/s per stream per card.
* **Cluster Aggregate Throughput:** Reached **~160 tokens/sec** combined throughput across both cards without cross-PCIe bus contention.

---

## 8. Known Constraints & Roadmap

* [x] Bare-metal Ubuntu 26.04 LTS migration.
* [x] ROCm RDNA2 hardware override validation (`gfx1030`).
* [x] Native `llama.cpp` dual-GPU systemd daemon deployment.
* [x] LiteLLM least-busy routing with Dashboards-as-Code observability.
* [ ] **vLLM Migration (Pending):** Transition from `llama.cpp` to containerized `vllm-rocm` with `--pipeline-parallel-size 2` and eager-mode kernel execution.

---

## 9. License

This project is open-source software licensed under the [MIT License](LICENSE).
