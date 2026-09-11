#!/bin/bash
# install_rocm.sh
# Securely adds the AMD ROCm repository and installs the compute stack on Ubuntu 24.04/26.04

set -e

echo "Cleaning potentially corrupted apt lists (AMD CDN issue)..."
sudo rm -rf /var/lib/apt/lists/*
sudo apt clean

echo "Creating the keyring directory..."
sudo mkdir --parents --mode=0755 /etc/apt/keyrings

echo "Downloading and storing the AMD GPG signing key..."
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null

echo "Adding the ROCm repository to your sources list (using noble branch)..."
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/debian noble main" | sudo tee /etc/apt/sources.list.d/rocm.list

echo "Updating package lists..."
sudo apt update

echo "Installing ROCm compute drivers, OpenCL, and SMI..."
# Note: Replaced the amdgpu-install wrapper script with native apt packages as discussed in the chat.
sudo apt install rocm-core rocm-opencl rocm-smi-lib -y

echo "Configuring user permissions..."
# Adding user to groups for non-root hardware acceleration
sudo usermod -aG video $USER
sudo usermod -aG render $USER
sudo usermod -aG docker $USER

echo "Applying the RDNA2 Hardware Override..."
# Forcing ROCm to accept the RX 6700 XT (Navi 22 / gfx1030)
echo 'export HSA_OVERRIDE_GFX_VERSION=10.3.0' | sudo tee -a /etc/profile.d/rocm-override.sh
source /etc/profile.d/rocm-override.sh

echo "Installation complete. Please REBOOT the node to ensure the kernel properly initializes the new user-space hooks."
