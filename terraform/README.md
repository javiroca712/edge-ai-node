# 🏗️ Terraform Infrastructure as Code (IaC)

This directory manages all in-cluster Kubernetes resources and Helm releases declaratively for the Edge AI Node platform.

## Architectural Separation of Concerns

```text
┌─────────────────────────────────────────────────────────┐
│                    Dev Laptop (Docker)                  │
│                                                         │
│  [Terraform Runner] ──> Manages K3s Cluster Resources   │
│  [Ansible Runner]   ──> Configures Bare-Metal Host OS   │
│  [K3s Server]       ──> Control Plane API (:6443)       │
└───────────────────────────┬─────────────────────────────┘
                            │ Tailscale Mesh
┌───────────────────────────▼─────────────────────────────┐
│               Edge Node (ubuntu01: Bare-Metal)          │
│                                                         │
│  K3s Agent ──> Executes containerized GPU/CPU workloads │
│  ROCm 6.x  ──> Hardware compute accelerators (gfx1030)  │
└─────────────────────────────────────────────────────────┘
```

* **Ansible (`ansible/`)**: Bare-metal operating system provisioning (GRUB flags, kernel modules, ROCm stack, swap configuration, K3s agent installation).
* **Terraform (`terraform/`)**: In-cluster declarative resources (Namespaces, PersistentVolumes, PersistentVolumeClaims, AMD GPU device plugin, deployments, services, Helm charts).

## Running via Docker on Dev Laptop (Zero Local Install)

To keep your host environment clean, run Terraform directly inside Docker:

```powershell
# Initialize providers
.\scripts\run_terraform.ps1 init

# Inspect planned changes
.\scripts\run_terraform.ps1 plan

# Apply infrastructure changes
.\scripts\run_terraform.ps1 apply -auto-approve
```
