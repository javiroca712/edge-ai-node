#!/bin/bash
# scripts/setup_replica_services.sh
# Automates the creation of two identical llama.cpp backends for Replica Parallelism.

set -e

echo "Stopping and disabling old monolithic service..."
sudo systemctl stop llama-api.service || true
sudo systemctl disable llama-api.service || true

for GPU_IDX in 0 1; do
    PORT=$((8082 + GPU_IDX))
    SERVICE_NAME="llama-api-${GPU_IDX}.service"
    SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
    
    echo "Writing ${SERVICE_PATH} for GPU ${GPU_IDX} on port ${PORT}..."
    
    sudo bash -c "cat > ${SERVICE_PATH}" <<EOF
[Unit]
Description=Llama.cpp Bare-Metal Inference API (GPU ${GPU_IDX})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=llama-api
Group=llama-api

# Hardware & Library Overrides
Environment="HSA_OVERRIDE_GFX_VERSION=10.3.0"
Environment="LD_LIBRARY_PATH=/opt/llama.cpp/build/bin"
Environment="HIP_VISIBLE_DEVICES=${GPU_IDX}"

# Execution
ExecStart=/opt/llama.cpp/build/bin/llama-server \\
  -m /opt/ai-models/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf \\
  --host 0.0.0.0 \\
  --port ${PORT} \\
  --metrics \\
  --n-gpu-layers 99 \\
  -c 16384

Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    echo "Reloading and enabling ${SERVICE_NAME}..."
    sudo systemctl daemon-reload
    sudo systemctl enable ${SERVICE_NAME}
    sudo systemctl restart ${SERVICE_NAME}
done

echo "Replica services started successfully."
