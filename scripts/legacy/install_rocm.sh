#!/bin/bash
# scripts/legacy/install_rocm.sh
# Installs ROCm compute and development packages natively on Ubuntu 26.04 LTS

set -e

echo "1. Cleaning legacy/stale external AMD repo lists (avoids CDN hash mismatches)..."
sudo rm -f /etc/apt/sources.list.d/rocm.list
sudo apt clean
sudo apt update

echo "2. Installing native Ubuntu 26.04 ROCm compute stack, compilers, and libraries..."
sudo apt install -y rocm-dev hipcc rocminfo libhipblas-dev libhipblas3 librocm-smi-dev librocm-smi64-7 rocm-device-libs-21

echo "3. Creating dedicated system service user (llama-api)..."
if ! id -u llama-api >/dev/null 2>&1; then
    sudo useradd -r -s /usr/sbin/nologin llama-api
fi
sudo usermod -aG video,render llama-api
sudo usermod -aG video,render $USER

echo "4. Applying RDNA2 Hardware Override for RX 6700 XT (gfx1030)..."
echo 'export HSA_OVERRIDE_GFX_VERSION=10.3.0' | sudo tee /etc/profile.d/rocm-override.sh
source /etc/profile.d/rocm-override.sh

echo "ROCm installation complete."
