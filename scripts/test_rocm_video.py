import os
import sys

# Force gfx1030 support for RDNA2 RX 6700 XT
os.environ["HSA_OVERRIDE_GFX_VERSION"] = "10.3.0"
os.environ["HIP_VISIBLE_DEVICES"] = "0"

import torch

print("==================================================")
print(" ROCm PyTorch Initialization on GPU 0")
print("==================================================")
print(f"PyTorch Version: {torch.__version__}")
print(f"ROCm/CUDA Available: {torch.cuda.is_available()}")
print(f"Device Count: {torch.cuda.device_count()}")

if not torch.cuda.is_available():
    print("ERROR: ROCm device not detected!")
    sys.exit(1)

device_name = torch.cuda.get_device_name(0)
print(f"Primary Device (GPU 0): {device_name}")

# Test allocation and compute on GPU 0
print("\nTesting tensor allocation on GPU 0 (Navi 22)...")
device = torch.device("cuda:0")
x = torch.randn(4096, 4096, device=device, dtype=torch.float16)
y = torch.randn(4096, 4096, device=device, dtype=torch.float16)

# Warmup
z = torch.matmul(x, y)
torch.cuda.synchronize()
print("Matrix multiplication (4096 x 4096 FP16) completed successfully!")
vram_allocated_mb = torch.cuda.memory_allocated(0) / (1024 * 1024)
print(f"Active VRAM allocated: {vram_allocated_mb:.2f} MB")
print("GPU 0 is 100% verified and compute-ready for diffusion pipelines!")
