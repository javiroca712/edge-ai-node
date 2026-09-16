#!/bin/bash
# scripts/legacy/setup_observability.sh
# Sets up node-exporter textfile collector, gpu-metrics telemetry cron, and Promtail log shipper

set -e

LOKI_URL=${1:-"http://100.112.218.62:3100/loki/api/v1/push"}

echo "1. Installing prometheus-node-exporter and tools..."
sudo apt update
sudo apt install -y prometheus-node-exporter unzip curl bc linux-tools-generic

echo "2. Configuring node-exporter textfile collector..."
sudo mkdir -p /var/lib/prometheus/node-exporter
sudo sed -i 's|^ARGS=.*|ARGS="--collector.textfile.directory=/var/lib/prometheus/node-exporter"|' /etc/default/prometheus-node-exporter
if ! grep -q "collector.textfile.directory" /etc/default/prometheus-node-exporter; then
    echo 'ARGS="--collector.textfile.directory=/var/lib/prometheus/node-exporter"' | sudo tee -a /etc/default/prometheus-node-exporter
fi
sudo systemctl restart prometheus-node-exporter

echo "3. Installing custom GPU and CPU telemetry script..."
sudo tee /usr/local/bin/gpu-metrics.sh << 'EOF'
#!/bin/bash
GPU0_UW=$(cat /sys/bus/pci/devices/0000:01:00.0/hwmon/hwmon*/power1_average 2>/dev/null)
GPU0_WATTS=$(echo "scale=2; $GPU0_UW / 1000000" | bc)

GPU1_UW=$(cat /sys/bus/pci/devices/0000:0b:00.0/hwmon/hwmon*/power1_average 2>/dev/null)
GPU1_WATTS=$(echo "scale=2; $GPU1_UW / 1000000" | bc)

CPU_WATTS=$(turbostat --Summary --show PkgWatt -q -n 1 2>/dev/null | awk 'NR==2 {print $1}')
CPU_TEMP=$(sensors | grep 'CPU Temperature' | awk '{print $3}' | tr -d '+°C')

TMP_FILE="/var/lib/prometheus/node-exporter/telemetry.prom.tmp"
FINAL_FILE="/var/lib/prometheus/node-exporter/telemetry.prom"

echo "amd_gpu0_power_watts $GPU0_WATTS" > $TMP_FILE
echo "amd_gpu1_power_watts $GPU1_WATTS" >> $TMP_FILE
echo "amd_cpu_power_watts $CPU_WATTS" >> $TMP_FILE
echo "amd_cpu_temperature_celsius $CPU_TEMP" >> $TMP_FILE

mv $TMP_FILE $FINAL_FILE
EOF
sudo chmod +x /usr/local/bin/gpu-metrics.sh

echo "4. Installing cron entries for 10-second metric polling..."
(sudo crontab -l 2>/dev/null | grep -v 'gpu-metrics.sh'; cat << 'EOF'
* * * * * /usr/local/bin/gpu-metrics.sh
* * * * * sleep 10; /usr/local/bin/gpu-metrics.sh
* * * * * sleep 20; /usr/local/bin/gpu-metrics.sh
* * * * * sleep 30; /usr/local/bin/gpu-metrics.sh
* * * * * sleep 40; /usr/local/bin/gpu-metrics.sh
* * * * * sleep 50; /usr/local/bin/gpu-metrics.sh
EOF
) | sudo crontab -

echo "5. Installing Promtail log shipper..."
if ! id -u promtail >/dev/null 2>&1; then
    sudo useradd -r -s /usr/sbin/nologin promtail
    sudo usermod -aG systemd-journal promtail
fi
sudo mkdir -p /etc/promtail /var/lib/promtail
sudo chown -R promtail:promtail /etc/promtail /var/lib/promtail

if [ ! -f /usr/local/bin/promtail ]; then
    curl -sL "https://github.com/grafana/loki/releases/download/v2.9.4/promtail-linux-amd64.zip" -o /tmp/promtail.zip
    sudo unzip -o /tmp/promtail.zip -d /tmp/
    sudo mv /tmp/promtail-linux-amd64 /usr/local/bin/promtail
    sudo chmod 755 /usr/local/bin/promtail
    rm -f /tmp/promtail.zip
fi

sudo tee /etc/promtail/config.yml << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: ${LOKI_URL}

scrape_configs:
  - job_name: systemd-journal
    journal:
      path: /var/log/journal
      max_age: 12h
      labels:
        job: systemd-journal
        host: ai-node
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
EOF
sudo chown promtail:promtail /etc/promtail/config.yml

sudo tee /etc/systemd/system/promtail.service << 'EOF'
[Unit]
Description=Promtail Log Shipper
After=network.target

[Service]
Type=simple
User=promtail
Group=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable promtail
sudo systemctl restart promtail

echo "Observability components setup complete."
