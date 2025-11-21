#!/bin/bash
# System Requirements Installation Script for PaaS Platform

set -e

echo "=========================================="
echo "PaaS Platform - Requirements Installation"
echo "=========================================="
echo ""

# Detect OS
if [ -f /etc/arch-release ]; then
    OS="arch"
    echo "Detected: Arch Linux"
elif [ -f /etc/debian_version ]; then
    OS="debian"
    echo "Detected: Debian/Ubuntu"
elif [ -f /etc/redhat-release ]; then
    OS="redhat"
    echo "Detected: RedHat/CentOS/Fedora"
else
    echo "Unsupported OS. This script supports Arch, Debian/Ubuntu, and RedHat-based systems."
    exit 1
fi

echo ""
echo "Installing required packages..."
echo ""

case $OS in
    arch)
        sudo pacman -Syu --needed --noconfirm \
            vagrant \
            ansible \
            libvirt \
            qemu-desktop \
            dnsmasq \
            ebtables \
            dmidecode \
            bridge-utils \
            openbsd-netcat
        ;;
    debian)
        sudo apt-get update
        sudo apt-get install -y \
            vagrant \
            ansible \
            libvirt-daemon-system \
            libvirt-clients \
            qemu-kvm \
            qemu-utils \
            dnsmasq \
            ebtables \
            bridge-utils \
            netcat-openbsd
        ;;
    redhat)
        sudo yum install -y \
            vagrant \
            ansible \
            libvirt \
            qemu-kvm \
            dnsmasq \
            ebtables \
            bridge-utils \
            nc
        ;;
esac

echo ""
echo "Starting and enabling libvirt service..."
sudo systemctl start libvirtd
sudo systemctl enable libvirtd

echo ""
echo "Adding current user to libvirt group..."
sudo usermod -a -G libvirt $USER

echo ""
echo "Installing vagrant-libvirt plugin..."
vagrant plugin install vagrant-libvirt

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "IMPORTANT: You must log out and log back in for group changes to take effect!"
echo ""
echo "After logging back in, verify installation with:"
echo "  ./setup.sh"
echo ""
