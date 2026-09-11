# rocm-override.sh
# Environment variables to force ROCm compatibility on consumer RDNA2 silicon
# This file is typically placed in /etc/profile.d/rocm-override.sh

export HSA_OVERRIDE_GFX_VERSION=10.3.0
