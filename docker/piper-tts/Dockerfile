FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    PIPER_MODEL_DIR=/opt/ai-models/tts \
    ARTIFACTS_DIR=/var/lib/ai-artifacts

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8084

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8084"]
