#!/bin/bash
# scripts/legacy/build_llama.sh
# Clones, patches, and natively compiles llama.cpp with HIPBLAS (ROCm) for gfx1030
# Also downloads the baseline Meta-Llama-3.1-8B-Instruct-Q4_K_M GGUF model

set -e

echo "1. Installing build dependencies and tools..."
sudo apt install -y build-essential cmake git wget

echo "2. Setting up directories..."
sudo mkdir -p /opt/llama.cpp /opt/ai-models
sudo chown -R llama-api:llama-api /opt/llama.cpp /opt/ai-models

echo "3. Cloning llama.cpp..."
if [ ! -d "/opt/llama.cpp/.git" ]; then
    sudo git clone https://github.com/ggml-org/llama.cpp.git /opt/llama.cpp
fi
cd /opt/llama.cpp

echo "4. Applying Flash Attention kernel patch for RDNA2 (Navi 22 max_blocks_per_sm)..."
sudo sed -i 's/GGML_ASSERT(max_blocks_per_sm > 0);/if (max_blocks_per_sm <= 0) { max_blocks_per_sm = 1; }/g' /opt/llama.cpp/ggml/src/ggml-cuda/fattn-common.cuh

echo "5. Generating CMake build configuration targeting gfx1030..."
sudo cmake -B build -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1030

echo "6. Compiling native ROCm release binary..."
sudo cmake --build build --config Release -j $(nproc)

echo "7. Downloading Meta-Llama-3.1-8B-Instruct-Q4_K_M GGUF model..."
if [ ! -f "/opt/ai-models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf" ]; then
    sudo wget -O /opt/ai-models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf \
      https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf
fi

echo "8. Enforcing service user permissions..."
sudo chown -R llama-api:llama-api /opt/llama.cpp /opt/ai-models

echo "Llama.cpp build and model provisioning complete."
