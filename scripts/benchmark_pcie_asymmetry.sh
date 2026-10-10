#!/bin/bash
# ==============================================================================
# Edge AI Node: PCIe 3.0 x16 vs x4 Asymmetry Empirical Benchmark Suite
# Tests identical payloads across GPU 0 (Navi 22, x16) and GPU 1 (Navi 22, x4)
# ==============================================================================
set -euo pipefail

MODEL_PATH="/opt/ai-models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
LLAMA_BENCH="/opt/llama.cpp/build/bin/llama-bench"
OUTPUT_DIR="/tmp/pcie_benchmark_results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

mkdir -p "${OUTPUT_DIR}"
export HSA_OVERRIDE_GFX_VERSION=10.3.0

echo "========================================================================"
echo " Starting PCIe Asymmetry Benchmark: GPU 0 (x16) vs GPU 1 (x4)"
echo " Timestamp: ${TIMESTAMP}"
echo " Model: ${MODEL_PATH}"
echo "========================================================================"

if [ ! -f "${MODEL_PATH}" ]; then
    echo "ERROR: Model file not found at ${MODEL_PATH}"
    exit 1
fi

if [ ! -f "${LLAMA_BENCH}" ]; then
    echo "ERROR: llama-bench binary not found at ${LLAMA_BENCH}"
    exit 1
fi

# ------------------------------------------------------------------------------
# Test 1: Cold Model Load Time (SATA SSD -> GPU VRAM)
# ------------------------------------------------------------------------------
echo ""
echo "[Test 1/3] Benchmarking Cold Model Load Time from SATA SSD..."

run_load_test() {
    local gpu_id=$1
    echo "  -> Dropping OS filesystem caches..."
    sync; echo 3 > /proc/sys/vm/drop_caches
    
    echo "  -> Loading model into GPU ${gpu_id}..."
    local start_time=$(date +%s%N)
    HIP_VISIBLE_DEVICES=${gpu_id} ${LLAMA_BENCH} -m "${MODEL_PATH}" -n 1 -p 1 -ngl 99 > /dev/null 2>&1
    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    echo "     GPU ${gpu_id} Cold Load Duration: ${duration_ms} ms"
    echo "${duration_ms}" > "${OUTPUT_DIR}/load_gpu${gpu_id}.txt"
}

run_load_test 0
run_load_test 1

# ------------------------------------------------------------------------------
# Test 2: llama-bench Prefill & Generation Matrix
# Tests: Prompt lengths 512, 1024, 2048, 4096; Gen lengths 128, 256
# ------------------------------------------------------------------------------
echo ""
echo "[Test 2/3] Benchmarking Prompt Processing (Prefill) & Token Generation..."

echo "  -> Running Benchmark on GPU 0 (PCIe 3.0 x16 - Direct CPU)..."
HIP_VISIBLE_DEVICES=0 ${LLAMA_BENCH} \
    -m "${MODEL_PATH}" \
    -ngl 99 \
    -p 512,1024,2048,4096 \
    -n 128,256 \
    -r 3 \
    -o json > "${OUTPUT_DIR}/bench_gpu0.json"

echo "  -> Running Benchmark on GPU 1 (PCIe 3.0 x4 - B450 Chipset)..."
HIP_VISIBLE_DEVICES=1 ${LLAMA_BENCH} \
    -m "${MODEL_PATH}" \
    -ngl 99 \
    -p 512,1024,2048,4096 \
    -n 128,256 \
    -r 3 \
    -o json > "${OUTPUT_DIR}/bench_gpu1.json"

# ------------------------------------------------------------------------------
# Test 3: Raw DMA Host-to-Device (H2D) & Device-to-Host (D2H) Transfer Speed
# ------------------------------------------------------------------------------
echo ""
echo "[Test 3/3] Benchmarking Raw DMA Memory Bandwidth (H2D / D2H)..."

cat << 'EOF' > /tmp/dma_bench.py
import torch
import time
import sys

gpu_id = int(sys.argv[1])
device = f"cuda:{gpu_id}"

# Allocate 1GB host tensor (pinned memory)
size_mb = 1024
num_elements = size_mb * 1024 * 1024 // 4
host_tensor = torch.empty(num_elements, dtype=torch.float32, pin_memory=True)
device_tensor = torch.empty(num_elements, dtype=torch.float32, device=device)

torch.cuda.synchronize()

# Warmup
device_tensor.copy_(host_tensor)
torch.cuda.synchronize()

# Test Host to Device (H2D)
runs = 10
start = time.perf_counter()
for _ in range(runs):
    device_tensor.copy_(host_tensor, non_blocking=False)
    torch.cuda.synchronize()
h2d_sec = (time.perf_counter() - start) / runs
h2d_gbps = (size_mb / 1024) / h2d_sec

# Test Device to Host (D2H)
start = time.perf_counter()
for _ in range(runs):
    host_tensor.copy_(device_tensor, non_blocking=False)
    torch.cuda.synchronize()
d2h_sec = (time.perf_counter() - start) / runs
d2h_gbps = (size_mb / 1024) / d2h_sec

print(f"{h2d_gbps:.2f},{d2h_gbps:.2f}")
EOF

if python3 -c "import torch" > /dev/null 2>&1; then
    echo "  -> Measuring DMA on GPU 0 (x16)..."
    python3 /tmp/dma_bench.py 0 > "${OUTPUT_DIR}/dma_gpu0.txt"
    echo "  -> Measuring DMA on GPU 1 (x4)..."
    python3 /tmp/dma_bench.py 1 > "${OUTPUT_DIR}/dma_gpu1.txt"
else
    echo "  -> PyTorch not in global python3; skipping raw DMA micro-benchmark."
    echo "N/A,N/A" > "${OUTPUT_DIR}/dma_gpu0.txt"
    echo "N/A,N/A" > "${OUTPUT_DIR}/dma_gpu1.txt"
fi

echo ""
echo "========================================================================"
echo " Benchmark Complete! Results stored in ${OUTPUT_DIR}"
echo "========================================================================"
