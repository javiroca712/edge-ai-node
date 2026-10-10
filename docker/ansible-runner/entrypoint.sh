#!/bin/bash
set -e

# Fix Windows NTFS permissions for OpenSSH inside container
if [ -d "/mnt/ssh" ]; then
    mkdir -p /root/.ssh
    cp -r /mnt/ssh/* /root/.ssh/ 2>/dev/null || true
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/id_* 2>/dev/null || true
    chmod 644 /root/.ssh/*.pub /root/.ssh/known_hosts 2>/dev/null || true
fi

exec ansible-playbook "$@"
