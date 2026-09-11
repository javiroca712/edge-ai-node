#!/bin/bash
# setup_os.sh
# Update the fresh OS and install sensor utilities to fix the Asus hardware sensor mapping bug

set -e

echo "Updating OS..."
sudo apt update && sudo apt upgrade -y

echo "Installing hardware sensor utilities..."
sudo apt install lm-sensors -y

echo "Probing the Asus motherboard to map correct hardware sensors..."
# We pipe yes | to sensors-detect --auto if it asks questions, but --auto usually handles it.
sudo sensors-detect --auto

echo "Checking true output..."
sensors
