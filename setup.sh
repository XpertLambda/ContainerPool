#!/bin/bash
# Quick setup script for the PaaS Platform

set -e

echo "==================================="
echo "PaaS Platform - Setup Script"
echo "==================================="
echo ""

# Detect OS
if [ -f /etc/arch-release ]; then
    echo "[OK] Detected: Arch Linux"
elif [ -f /etc/debian_version ]; then
    echo "[OK] Detected: Debian/Ubuntu"
elif [ -f /etc/redhat-release ]; then
    echo "[OK] Detected: RedHat/Fedora/CentOS"
else
    echo "[WARNING] Unknown distribution (supported: Arch, Debian/Ubuntu, RedHat)"
fi

# Check for required tools
echo ""
echo "Checking prerequisites..."

command -v vagrant >/dev/null 2>&1 || {
    echo "[ERROR] Vagrant is not installed"
    echo "  Run ./requirements.sh to install all dependencies"
    exit 1
}
echo "[OK] Vagrant installed"

command -v ansible >/dev/null 2>&1 || {
    echo "[ERROR] Ansible is not installed"
    echo "  Run ./requirements.sh to install all dependencies"
    exit 1
}
echo "[OK] Ansible installed"

# Check if libvirt is available
if systemctl is-active --quiet libvirtd; then
    echo "[OK] libvirtd service is running"
else
    echo "[WARNING] libvirtd service is not running"
    echo "  Start with: sudo systemctl start libvirtd"
    exit 1
fi

# Check for vagrant-libvirt plugin
if vagrant plugin list | grep -q vagrant-libvirt; then
    echo "[OK] vagrant-libvirt plugin installed"
else
    echo "[ERROR] vagrant-libvirt plugin not found"
    echo "  Installing vagrant-libvirt plugin..."
    vagrant plugin install vagrant-libvirt
fi

echo ""
echo "==================================="
echo "All prerequisites are satisfied!"
echo "==================================="
echo ""
echo "Next steps:"
echo "1. cd infrastructure"
echo "2. vagrant up"
echo ""
echo "Access the platform at: http://192.168.121.10:5000"
echo "Or via localhost: http://localhost:5000"
echo ""
