#!/bin/sh
# Emergency service shutdown
# Usage: service_kill.sh <service_name>

set -e

if [ $# -ne 1 ]; then
    echo "ERROR: Missing service name"
    echo "Usage: $0 <service_name>"
    exit 1
fi

SERVICE_NAME="$1"
BASE_DIR="${KK_BASE_DIR:-/opt/keyboard_kowboys}"
LOG_DIR="${KK_LOG_DIR:-$BASE_DIR/logs}"

echo "=== Keyboard Kowboys service-kill ==="
echo "Emergency shutdown of service: $SERVICE_NAME"
echo ""

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Root privileges required for service management"
    exit 1
fi

# Try systemd first
if command -v systemctl >/dev/null 2>&1; then
    echo "Using systemd to kill service..."

    # Save logs before shutdown
    if command -v journalctl >/dev/null 2>&1; then
        LOG_FILE="$LOG_DIR/killed-$SERVICE_NAME-$(date +%Y%m%d-%H%M%S).log"
        echo "Saving service logs to: $LOG_FILE"
        journalctl -u "$SERVICE_NAME" -n 100 > "$LOG_FILE" 2>/dev/null || echo "Could not save logs" > "$LOG_FILE"
    fi

    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    systemctl mask "$SERVICE_NAME" 2>/dev/null || true

    echo "Service $SERVICE_NAME stopped, disabled, and masked (systemd)"

# Try init.d
elif [ -f "/etc/init.d/$SERVICE_NAME" ]; then
    echo "Using init.d to kill service..."

    /etc/init.d/"$SERVICE_NAME" stop 2>/dev/null || true

    # Try to disable using available tools
    if command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d "$SERVICE_NAME" disable 2>/dev/null || true
        echo "Service $SERVICE_NAME stopped and disabled (update-rc.d)"
    elif command -v chkconfig >/dev/null 2>&1; then
        chkconfig "$SERVICE_NAME" off 2>/dev/null || true
        echo "Service $SERVICE_NAME stopped and disabled (chkconfig)"
    else
        echo "Service $SERVICE_NAME stopped (but could not disable - no update-rc.d or chkconfig found)"
    fi

# Try BSD-style service command
elif command -v service >/dev/null 2>&1; then
    echo "Using service command to kill service..."
    service "$SERVICE_NAME" stop 2>/dev/null || true
    echo "Service $SERVICE_NAME stopped (service command)"
    echo "WARNING: Could not disable service - manual intervention required"

else
    echo "ERROR: No supported service management system found"
    echo "Tried: systemctl, /etc/init.d, service command"
    exit 1
fi

echo ""
echo "Service $SERVICE_NAME has been killed"
if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
    echo "Logs saved to: $LOG_FILE"
fi
