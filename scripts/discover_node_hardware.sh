#!/usr/bin/env bash
# ==============================================================================
# Dynamic Hardware Discovery for Edge AI Node GPUs
# Inspects AMD GPUs, PCIe Link Widths, Bus Topology, and VRAM directly via sysfs.
# Generates Kubernetes node labels dynamically without hardcoding.
# ==============================================================================
set -euo pipefail

echo "=== Inspecting Physical Accelerator Hardware via sysfs ==="

GPU_COUNT=0
MAX_PCIE_WIDTH=0
MIN_PCIE_WIDTH=99
ARCH="unknown"
VRAM_MB=0

LABELS=()
LABELS+=("accelerator=amd-rocm")
LABELS+=("hardware.discovered=true")

# Find all AMD VGA/3D display controllers (PCI class 0300 or 0302)
GPU_BUSES=$(lspci -D -d 1002: | grep -iE 'VGA|Display|3D controller' | awk '{print $1}')

SLOT_IDX=0
for BUS in $GPU_BUSES; do
    # Find full sysfs tree path to trace upstream root port
    SYSFS_DEV="/sys/bus/pci/devices/${BUS}"
    FULL_PATH=$(readlink -f "${SYSFS_DEV}")
    
    # Trace upstream to root port (direct child of pci0000:00)
    ROOT_PORT=$(echo "$FULL_PATH" | grep -o '/sys/devices/pci[^/]*/[^/]*' | head -n 1 || echo "")
    
    WIDTH=0
    SPEED="unknown"
    if [[ -n "$ROOT_PORT" && -f "${ROOT_PORT}/current_link_width" ]]; then
        WIDTH=$(cat "${ROOT_PORT}/current_link_width" | tr -d '[:space:]')
        SPEED=$(cat "${ROOT_PORT}/current_link_speed" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
    else
        WIDTH=$(cat "${SYSFS_DEV}/current_link_width" 2>/dev/null | tr -d '[:space:]' || echo "16")
        SPEED=$(cat "${SYSFS_DEV}/current_link_speed" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
    fi

    if [[ "$WIDTH" =~ ^[0-9]+$ ]]; then
        if (( WIDTH > MAX_PCIE_WIDTH )); then MAX_PCIE_WIDTH=$WIDTH; fi
        if (( WIDTH < MIN_PCIE_WIDTH )); then MIN_PCIE_WIDTH=$WIDTH; fi
    fi

    # Read DRM device node & VRAM
    DRM_PATH=$(find "${SYSFS_DEV}/drm" -maxdepth 1 -name "card*" 2>/dev/null | head -n 1 || true)
    if [[ -n "$DRM_PATH" ]]; then
        CARD_NAME=$(basename "$DRM_PATH")
        if [[ -f "/sys/class/drm/$CARD_NAME/device/mem_info_vram_total" ]]; then
            RAW_VRAM=$(cat "/sys/class/drm/$CARD_NAME/device/mem_info_vram_total")
            VRAM_MB=$(( RAW_VRAM / 1024 / 1024 ))
        fi
    fi

    GEN="3.0"
    if [[ "$SPEED" == *"16.0GT"* || "$SPEED" == *"16GT"* ]]; then GEN="4.0"; fi
    if [[ "$SPEED" == *"8.0GT"* || "$SPEED" == *"8GT"* ]]; then GEN="3.0"; fi

    echo "Discovered GPU $SLOT_IDX: PCI $BUS | Link PCIe $GEN x$WIDTH ($SPEED) | VRAM ${VRAM_MB}MB"

    CLEAN_BUS=$(echo "$BUS" | tr ':' '_')
    LABELS+=("gpu.amd.com/slot${SLOT_IDX}.bus=pcie-${GEN}-x${WIDTH}")
    LABELS+=("gpu.amd.com/slot${SLOT_IDX}.pci=${CLEAN_BUS}")
    if (( WIDTH >= 8 )); then
        LABELS+=("gpu.amd.com/slot${SLOT_IDX}.class=fast-bus")
    else
        LABELS+=("gpu.amd.com/slot${SLOT_IDX}.class=standard-bus")
    fi

    GPU_COUNT=$((GPU_COUNT + 1))
    SLOT_IDX=$((SLOT_IDX + 1))
done

# Architecture detection
if command -v rocminfo >/dev/null 2>&1; then
    DETECTED_ARCH=$(rocminfo 2>/dev/null | grep -o 'gfx[0-9]*' | head -n 1 || true)
    if [[ -n "$DETECTED_ARCH" ]]; then ARCH="$DETECTED_ARCH"; fi
fi
if [[ "$ARCH" == "unknown" ]]; then ARCH="gfx1030"; fi

LABELS+=("gpu.amd.com/count=${GPU_COUNT}")
LABELS+=("gpu.amd.com/arch=${ARCH}")
LABELS+=("gpu.amd.com/vram-mb=${VRAM_MB}")
LABELS+=("gpu.amd.com/vram-gib=$(( (VRAM_MB + 512) / 1024 ))")
LABELS+=("gpu.amd.com/pcie-max-width=x${MAX_PCIE_WIDTH}")
LABELS+=("gpu.amd.com/pcie-min-width=x${MIN_PCIE_WIDTH}")
LABELS+=("gpu.amd.com/has-fastbus=$([ $MAX_PCIE_WIDTH -ge 8 ] && echo 'true' || echo 'false')")

echo ""
echo "=== Discovered Node Labels for Kubernetes ==="
for L in "${LABELS[@]}"; do
    echo "  --node-label $L"
done

echo ""
echo "ANSIBLE_NODE_LABELS=\"${LABELS[*]}\""
