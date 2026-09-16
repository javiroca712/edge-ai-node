#!/bin/bash
# scripts/legacy/setup_os.sh
# Bare-metal OS initialization, storage expansion, PCIe kernel tuning, and hardware sensors

set -e

echo "1. Updating OS package repositories and base system..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential dkms git bc sysstat lm-sensors linux-headers-$(uname -r)

echo "2. Expanding LVM volume group to 100% capacity..."
if [ -e /dev/mapper/ubuntu--vg-ubuntu--lv ]; then
    sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv || true
    sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv || true
fi

echo "3. Configuring 16GB Swap file for 4GB host RAM constraint..."
if [ ! -f /swap.img ] || [ $(stat -c%s "/swap.img" 2>/dev/null || echo 0) -lt 16000000000 ]; then
    sudo swapoff /swap.img 2>/dev/null || true
    sudo fallocate -l 16G /swap.img
    sudo chmod 600 /swap.img
    sudo mkswap /swap.img
    sudo swapon /swap.img
    if ! grep -q "/swap.img" /etc/fstab; then
        echo '/swap.img none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
fi

echo "4. Applying PCIe stability and IOMMU flags to GRUB..."
sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash iommu=pt pcie_aspm=off"/' /etc/default/grub
sudo update-grub

echo "5. Installing ASUS WMI Sensors DKMS kernel driver to prevent thermal throttle panics..."
if ! dkms status | grep -q "asus-wmi-sensors"; then
    rm -rf /tmp/asus-wmi-sensors
    git clone https://github.com/electrified/asus-wmi-sensors.git /tmp/asus-wmi-sensors
    cd /tmp/asus-wmi-sensors
    sudo make dkms
    sudo modprobe asus-wmi-sensors
    cd -
fi

echo "6. Probing hardware sensors..."
sudo sensors-detect --auto
sensors

echo "Base OS tuning completed successfully."
