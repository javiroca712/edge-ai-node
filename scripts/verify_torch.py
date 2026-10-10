import torch

print("==========================================")
print("PyTorch Version:", torch.__version__)
print("ROCm/CUDA Available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("Device Count:", torch.cuda.device_count())
    print("Device 0 Name:", torch.cuda.get_device_name(0))
    # Quick tensor test
    t = torch.ones((2, 2), device="cuda:0")
    print("Tensor on GPU 0:", t.sum().item())
print("==========================================")
