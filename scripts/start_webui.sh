#!/bin/bash
# start_webui.sh
# Runs Open WebUI and points it to the running backend
# WARNING: This contains the Ollama footprint (OLLAMA_BASE_URL) that must be rewritten for vLLM.

set -e

# Replace <YOUR_TAILSCALE_IP> with the actual IP address of the server
SERVER_IP="<YOUR_TAILSCALE_IP>"

docker run -d -p 3000:8080 \
  --add-host=host.docker.internal:host-gateway \
  -e OPENAI_API_BASE_URL="http://host.docker.internal:4000/v1" \
  -e OPENAI_API_KEY="sk-1234" \
  -v open-webui:/app/backend/data \
  --name open-webui \
  --restart always \
  ghcr.io/open-webui/open-webui:main

echo "Open WebUI started on port 3000."
