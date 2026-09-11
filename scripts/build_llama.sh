#!/bin/bash
# build_llama.sh
# Clones and natively compiles llama.cpp with HIPBLAS (ROCm) support for gfx1030

set -e

echo "Installing build dependencies..."
sudo apt install git build-essential cmake -y

echo "Cloning llama.cpp..."
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp

echo "Compiling native ROCm Binary for gfx1030 (RX 6700 XT)..."
# The C++ patch for fattn-common.cuh to fix max_blocks_per_sm > 0 is assumed to be manually applied before running cmake if required.

# Generate build files targeting gfx1030
cmake -B build -DGGML_HIPBLAS=ON -DAMDGPU_TARGETS=gfx1030

# Compile
cmake --build build --config Release -j $(nproc)

echo "Build complete."
