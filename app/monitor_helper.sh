#!/bin/bash
# Manual Container Health Check and Recovery Script

SCRIPT_DIR="/opt/my-paas"

show_menu() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         Container Health Monitor & Recovery                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo " MONITORING:"
    echo "  1) Check container health and auto-recover"
    echo "  2) View monitor logs (live)"
    echo "  3) View monitor logs (last 50 lines)"
    echo ""
    echo " SERVICE MANAGEMENT:"
    echo "  4) Check monitor service status"
    echo "  5) Start monitor timer"
    echo "  6) Stop monitor timer"
    echo "  7) Restart monitor timer"
    echo "  8) Run monitor manually (one-time)"
    echo ""
    echo " CONFIGURATION:"
    echo "  9) Show monitor schedule"
    echo " 10) Change monitor interval"
    echo ""
    echo " 11) Exit"
    echo ""
}

run_health_check() {
    echo "Running container health check..."
    echo ""
    cd $SCRIPT_DIR
    source venv/bin/activate
    python container_monitor.py
}

view_logs_live() {
    echo "Viewing monitor logs (press Ctrl+C to exit)..."
    echo ""
    tail -f /opt/my-paas/container_monitor.log
}

view_logs_recent() {
    echo "Recent monitor logs:"
    echo "═══════════════════════════════════════════════════════════════"
    tail -50 /opt/my-paas/container_monitor.log
}

check_service_status() {
    echo "Container Monitor Service Status:"
    echo "═══════════════════════════════════════════════════════════════"
    systemctl status container-monitor.service --no-pager
    echo ""
    echo "Container Monitor Timer Status:"
    echo "═══════════════════════════════════════════════════════════════"
    systemctl status container-monitor.timer --no-pager
    echo ""
    echo "Next scheduled run:"
    systemctl list-timers container-monitor.timer --no-pager
}

start_monitor() {
    echo "Starting container monitor timer..."
    sudo systemctl start container-monitor.timer
    sudo systemctl enable container-monitor.timer
    echo "[OK] Monitor timer started and enabled"
}

stop_monitor() {
    echo "Stopping container monitor timer..."
    sudo systemctl stop container-monitor.timer
    echo "[OK] Monitor timer stopped"
}

restart_monitor() {
    echo "Restarting container monitor timer..."
    sudo systemctl restart container-monitor.timer
    echo "[OK] Monitor timer restarted"
}

run_manual() {
    echo "Running monitor manually (one-time check)..."
    echo ""
    sudo systemctl start container-monitor.service
    echo ""
    echo "Check logs for results:"
    echo "  journalctl -u container-monitor.service -n 50"
}

show_schedule() {
    echo "Current Monitor Schedule:"
    echo "═══════════════════════════════════════════════════════════════"
    systemctl cat container-monitor.timer
}

change_interval() {
    echo "Change Monitor Interval"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Current configuration:"
    grep "OnUnitActiveSec" /etc/systemd/system/container-monitor.timer
    echo ""
    echo "Enter new interval (e.g., 1min, 5min, 10min, 30sec):"
    read interval
    
    if [ -z "$interval" ]; then
        echo "Cancelled"
        return
    fi
    
    echo ""
    echo "Updating timer to run every $interval..."
    
    sudo sed -i "s/OnUnitActiveSec=.*/OnUnitActiveSec=$interval/" /etc/systemd/system/container-monitor.timer
    sudo systemctl daemon-reload
    sudo systemctl restart container-monitor.timer
    
    echo "[OK] Monitor interval updated to $interval"
    echo ""
    echo "New configuration:"
    systemctl list-timers container-monitor.timer --no-pager
}

# Main loop
clear

while true; do
    show_menu
    read -p "Select option: " choice
    echo ""
    
    case $choice in
        1) run_health_check ;;
        2) view_logs_live ;;
        3) view_logs_recent ;;
        4) check_service_status ;;
        5) start_monitor ;;
        6) stop_monitor ;;
        7) restart_monitor ;;
        8) run_manual ;;
        9) show_schedule ;;
        10) change_interval ;;
        11) echo "Goodbye!"; exit 0 ;;
        *) echo "Invalid option" ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    clear
done
