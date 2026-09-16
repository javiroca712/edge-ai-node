#!/bin/bash

# 1. Top GPU (PCI 01:00.0) Power Read
GPU0_UW=$(cat /sys/bus/pci/devices/0000:01:00.0/hwmon/hwmon*/power1_average 2>/dev/null)
GPU0_WATTS=$(echo "scale=2; $GPU0_UW / 1000000" | bc)

# 2. Bottom GPU (PCI 0b:00.0) Power Read
GPU1_UW=$(cat /sys/bus/pci/devices/0000:0b:00.0/hwmon/hwmon*/power1_average 2>/dev/null)
GPU1_WATTS=$(echo "scale=2; $GPU1_UW / 1000000" | bc)

# 3. CPU Power (RAPL)
CPU_WATTS=$(turbostat --Summary --show PkgWatt -q -n 1 2>/dev/null | awk 'NR==2 {print $1}')

# 4. CPU Temp (ASUS WMI)
CPU_TEMP=$(sensors | grep 'CPU Temperature' | awk '{print $3}' | tr -d '+°C')

# 5. Write to Prometheus Exporter Target
TMP_FILE="/var/lib/prometheus/node-exporter/telemetry.prom.tmp"
FINAL_FILE="/var/lib/prometheus/node-exporter/telemetry.prom"

echo "amd_gpu0_power_watts $GPU0_WATTS" > $TMP_FILE
echo "amd_gpu1_power_watts $GPU1_WATTS" >> $TMP_FILE
echo "amd_cpu_power_watts $CPU_WATTS" >> $TMP_FILE
echo "amd_cpu_temperature_celsius $CPU_TEMP" >> $TMP_FILE

# 6. Atomic swap
mv $TMP_FILE $FINAL_FILE
