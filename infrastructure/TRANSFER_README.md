# Container Pool PaaS Platform - Portable Box Transfer Guide

## What You're Receiving

This package contains a fully configured PaaS (Platform-as-a-Service) platform:

| Component | Details |
|-----------|---------|
| VM | Ubuntu 22.04 LTS with Docker |
| Application | Flask web app on port 5000 |
| Container Pool | 15 pre-built containers ready for instant assignment |
| Monitoring | Auto-recovery system running every 30 seconds |
| Database | SQLite with user/container data |

## Requirements

**Your system MUST have:**

1. **Linux OS** (Arch, Ubuntu, Debian, Fedora, etc.)
2. **KVM/libvirt** virtualization
3. **Vagrant** with vagrant-libvirt plugin

### Quick Requirements Check

```bash
# Check if KVM is available
lsmod | grep kvm

# Check if libvirt is running
sudo systemctl status libvirtd

# Check Vagrant
vagrant --version

# Check vagrant-libvirt plugin
vagrant plugin list | grep libvirt
```

### Install Requirements (if needed)

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install -y vagrant libvirt-daemon-system libvirt-clients qemu-kvm
vagrant plugin install vagrant-libvirt
sudo usermod -a -G libvirt $USER
# Log out and back in for group changes
```

**Arch Linux:**
```bash
sudo pacman -S vagrant libvirt qemu-desktop dnsmasq
vagrant plugin install vagrant-libvirt
sudo usermod -a -G libvirt $USER
sudo systemctl enable --now libvirtd
# Log out and back in for group changes
```

**Fedora:**
```bash
sudo dnf install -y vagrant libvirt qemu-kvm
vagrant plugin install vagrant-libvirt
sudo usermod -a -G libvirt $USER
# Log out and back in for group changes
```

## Files Included

```
portable-package/
├── my-paas-portable.box     # The VM image (3.3 GB)
├── Vagrantfile.portable     # Configuration for the box
└── TRANSFER_README.md       # This file
```

## Installation Steps

### Step 1: Add the Box to Vagrant

```bash
# Navigate to the folder containing the box
cd /path/to/portable-package

# Add the box to Vagrant (this imports the VM image)
vagrant box add my-paas-portable my-paas-portable.box

# This will take a few minutes depending on your disk speed
```

### Step 2: Set Up the Working Directory

```bash
# Create a working directory
mkdir ~/paas-platform
cd ~/paas-platform

# Copy the Vagrantfile
cp /path/to/portable-package/Vagrantfile.portable Vagrantfile
```

### Step 3: Start the Platform

```bash
# Start the VM
vagrant up

# This will:
# - Create the VM from the imported box
# - Configure networking
# - Start all services automatically
```

### Step 4: Access the Platform

Open your browser and go to:
- **http://localhost:5000** or
- **http://192.168.121.183:5000**

## Quick Commands

```bash
# SSH into the VM
vagrant ssh

# Check platform status
vagrant ssh -c "sudo systemctl status paas-app"

# View container pool
vagrant ssh -c "cd /opt/my-paas && source venv/bin/activate && python pool_manager.py --status"

# Stop the VM
vagrant halt

# Start the VM
vagrant up

# Destroy the VM (keeps the box for re-creation)
vagrant destroy
```

## Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| VM SSH | vagrant | vagrant |
| Ubuntu-SSH containers | devuser | devpass123 |

## Network Ports

| Port | Service |
|------|---------|
| 5000 | Flask Web App |
| 8000-8099 | Nginx containers |
| 8100-8199 | Apache containers |
| 8200-8299 | Python containers |
| 8300-8399 | Node.js containers |
| 2200-2210 | SSH containers |

## Troubleshooting

### VM won't start
```bash
# Check libvirt is running
sudo systemctl start libvirtd

# Check you're in libvirt group
groups | grep libvirt

# If not, add yourself and re-login
sudo usermod -a -G libvirt $USER
```

### Can't access web interface
```bash
# Check Flask is running
vagrant ssh -c "sudo systemctl status paas-app"

# Restart if needed
vagrant ssh -c "sudo systemctl restart paas-app"

# Check VM IP
vagrant ssh -c "hostname -I"
```

### Containers not available
```bash
# Initialize/reinitialize the pool
vagrant ssh -c "cd /opt/my-paas && source venv/bin/activate && python pool_manager.py --init"
```

## Removing the Platform

```bash
# Stop and delete the VM
vagrant destroy

# Remove the imported box
vagrant box remove my-paas-portable

# Delete the working directory
rm -rf ~/paas-platform
```

## Support

This is a self-contained PaaS platform. All services are configured to start automatically when the VM boots.

For issues, check the logs:
```bash
# Flask app logs
vagrant ssh -c "sudo journalctl -u paas-app -n 50"

# Container monitor logs  
vagrant ssh -c "tail -50 /opt/my-paas/container_monitor.log"

# Docker status
vagrant ssh -c "docker ps -a"
```
