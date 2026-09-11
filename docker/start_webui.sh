#!/bin/bash
# start_webui.sh
# Runs Open WebUI and points it to the running backend
# WARNING: This contains the Ollama footprint (OLLAMA_BASE_URL) that must be rewritten for vLLM.

set -e

# Replace <YOUR_TAILSCALE_IP> with the actual IP address of the server
SERVER_IP="<YOUR_TAILSCALE_IP>"

docker run -d -p 3000:8080 \
  --add-host=host.docker.internal:host-gateway \
  -e OLLAMA_BASE_URL="http://${SERVER_IP}:8082" \
  -v open-webui:/app/backend/data \
  --name open-webui \
  --restart always \
  ghcr.io/open-webui/open-webui:main

echo "Open WebUI started on port 3000."
