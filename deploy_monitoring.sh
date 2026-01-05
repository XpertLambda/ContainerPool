#!/bin/bash
# Deploy Container Monitoring System to Existing Installation

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Container Auto-Recovery System - Manual Deployment          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if we're on the host (not in VM)
if [ -d "/opt/my-paas" ]; then
    echo "[ERROR] This script should be run from the HOST machine, not inside the VM"
    exit 1
fi

# Check if infrastructure directory exists
if [ ! -d "infrastructure" ]; then
    echo "[ERROR] Please run this script from the project root directory"
    exit 1
fi

echo "This script will deploy the container monitoring system to your VM."
echo ""
echo "Steps:"
echo "  1. Copy monitoring files to VM"
echo "  2. Install systemd service and timer"
echo "  3. Start monitoring service"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo "Step 1: Copying files to VM..."
echo "═══════════════════════════════════════════════════════════════"

# Copy monitoring script
echo "  → container_monitor.py"
scp app/container_monitor.py vagrant@192.168.121.183:/tmp/

# Copy helper scripts
echo "  → monitor_helper.sh"
scp app/monitor_helper.sh vagrant@192.168.121.183:/tmp/

echo "  → test_recovery.sh"
scp app/test_recovery.sh vagrant@192.168.121.183:/tmp/

# Copy systemd files
echo "  → container-monitor.service"
scp app/container-monitor.service vagrant@192.168.121.183:/tmp/

echo "  → container-monitor.timer"
scp app/container-monitor.timer vagrant@192.168.121.183:/tmp/

echo ""
echo "Step 2: Installing on VM..."
echo "═══════════════════════════════════════════════════════════════"

ssh vagrant@192.168.121.183 << 'REMOTE_SCRIPT'
# Move files to correct locations
echo "  → Moving files to /opt/my-paas/"
sudo mv /tmp/container_monitor.py /opt/my-paas/
sudo mv /tmp/monitor_helper.sh /opt/my-paas/
sudo mv /tmp/test_recovery.sh /opt/my-paas/

# Set permissions
echo "  → Setting permissions"
sudo chmod +x /opt/my-paas/container_monitor.py
sudo chmod +x /opt/my-paas/monitor_helper.sh
sudo chmod +x /opt/my-paas/test_recovery.sh
sudo chown vagrant:vagrant /opt/my-paas/container_monitor.py
sudo chown vagrant:vagrant /opt/my-paas/monitor_helper.sh
sudo chown vagrant:vagrant /opt/my-paas/test_recovery.sh

# Move systemd files
echo "  → Installing systemd service and timer"
sudo mv /tmp/container-monitor.service /etc/systemd/system/
sudo mv /tmp/container-monitor.timer /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/container-monitor.service
sudo chmod 644 /etc/systemd/system/container-monitor.timer

# Reload systemd
echo "  → Reloading systemd"
sudo systemctl daemon-reload

# Enable and start timer
echo "  → Enabling and starting monitor timer"
sudo systemctl enable container-monitor.timer
sudo systemctl start container-monitor.timer

echo ""
echo "Step 3: Verifying installation..."
echo "═══════════════════════════════════════════════════════════════"

# Check timer status
echo "  → Timer status:"
systemctl status container-monitor.timer --no-pager | head -5

echo ""
echo "  → Next scheduled run:"
systemctl list-timers container-monitor.timer --no-pager

echo ""
echo "  → Running initial health check..."
cd /opt/my-paas
source venv/bin/activate
python container_monitor.py
REMOTE_SCRIPT

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Deployment Complete!                                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Container Auto-Recovery is now active!"
echo ""
echo "✓ Monitoring every 2 minutes"
echo "✓ Automatic recovery enabled"
echo "✓ Logs at: /opt/my-paas/container_monitor.log"
echo ""
echo "Useful commands:"
echo ""
echo "  # View live logs"
echo "  ssh vagrant@192.168.121.183 \"tail -f /opt/my-paas/container_monitor.log\""
echo ""
echo "  # Interactive monitor helper"
echo "  ssh vagrant@192.168.121.183 \"sudo bash /opt/my-paas/monitor_helper.sh\""
echo ""
echo "  # Test recovery"
echo "  ssh vagrant@192.168.121.183 \"bash /opt/my-paas/test_recovery.sh\""
echo ""
echo "  # Check status"
echo "  ssh vagrant@192.168.121.183 \"systemctl status container-monitor.timer\""
echo ""
echo "See CONTAINER_MONITORING.md for complete documentation."
echo ""
