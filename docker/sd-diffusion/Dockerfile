# ==============================================================================
# Containerized stable-diffusion.cpp (sd-cli) with AMD ROCm (gfx1030) Support
# ==============================================================================
# Multi-stage build for AnimateDiff video generation without host library mounts.
# ==============================================================================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    HSA_OVERRIDE_GFX_VERSION=10.3.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    ca-certificates \
    libhipblas-dev \
    librocsolver-dev \
    librocblas-dev \
    rocm-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
ARG SD_CPP_VERSION=master
RUN git clone --depth 1 https://github.com/leejet/stable-diffusion.cpp.git . && \
    git submodule update --init --recursive

# Apply RDNA2 Flash Attention bug fix in ggml submodule
RUN if [ -f ggml/src/ggml-cuda/fattn-common.cuh ]; then \
      sed -i 's/GGML_ASSERT(max_blocks_per_sm > 0);/if (max_blocks_per_sm <= 0) { max_blocks_per_sm = 1; }/' ggml/src/ggml-cuda/fattn-common.cuh; \
    fi

RUN cmake -B build \
    -DSD_HIPBLAS=ON \
    -DAMDGPU_TARGETS=gfx1030 \
    -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build --config Release -j$(nproc) --target sd-cli

# ==============================================================================
# Runtime Stage
# ==============================================================================
FROM ubuntu:24.04 AS runner

ENV DEBIAN_FRONTEND=noninteractive \
    HSA_OVERRIDE_GFX_VERSION=10.3.0 \
    LD_LIBRARY_PATH=/opt/rocm/lib:/usr/local/lib

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    libgomp1 \
    libnuma1 \
    rocminfo \
    libhipblas0 \
    librocblas0 \
    librocsolver0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/build/bin/sd-cli /usr/local/bin/sd-cli

ENTRYPOINT ["sd-cli"]
CMD ["--help"]
