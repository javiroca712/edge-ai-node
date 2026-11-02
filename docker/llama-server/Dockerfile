# ==============================================================================
# Containerized llama.cpp Server with AMD ROCm (gfx1030) Support
# ==============================================================================
# Multi-stage build producing a standalone inference container without
# requiring hostPath mounts of host libraries or host binaries.
# ==============================================================================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    HSA_OVERRIDE_GFX_VERSION=10.3.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    ca-certificates \
    curl \
    libhipblas-dev \
    librocsolver-dev \
    librocblas-dev \
    rocm-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
ARG LLAMACPP_VERSION=b4000
RUN git clone --depth 1 --branch ${LLAMACPP_VERSION} https://github.com/ggml-org/llama.cpp.git .

# Apply RDNA2 Flash Attention max_blocks_per_sm guard if present
RUN if [ -f ggml/src/ggml-cuda/fattn-common.cuh ]; then \
      sed -i 's/GGML_ASSERT(max_blocks_per_sm > 0);/if (max_blocks_per_sm <= 0) { max_blocks_per_sm = 1; }/' ggml/src/ggml-cuda/fattn-common.cuh; \
    fi

RUN cmake -B build \
    -DGGML_HIP=ON \
    -DAMDGPU_TARGETS=gfx1030 \
    -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build --config Release -j$(nproc) --target llama-server

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

COPY --from=builder /src/build/bin/llama-server /usr/local/bin/llama-server

EXPOSE 8083

ENTRYPOINT ["llama-server"]
CMD ["--host", "0.0.0.0", "--port", "8083", "--metrics"]
