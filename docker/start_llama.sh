#!/bin/bash
# start_llama.sh
# Runs the ROCm-enabled llama.cpp server in Docker

set -e

# Ensure model directory exists
mkdir -p ~/ai-models

# Run the benchmark container mapping devices and applying hardware overrides
docker run -d --name llm-benchmark \
  --device=/dev/kfd --device=/dev/dri \
  -e HSA_OVERRIDE_GFX_VERSION=10.3.0 \
  -v ~/ai-models:/models \
  -p 8080:8080 \
  ghcr.io/ggerganov/llama.cpp:server-rocm \
  -m /models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf \
  --host 0.0.0.0 --port 8080 --n-gpu-layers 99

echo "Container started. Check logs with: docker logs -f llm-benchmark"
