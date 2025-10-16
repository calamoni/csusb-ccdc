#!/bin/sh
# Restore a killed service
# Usage: service_restore.sh <service_name>

set -e

if [ $# -ne 1 ]; then
    echo "ERROR: Missing service name"
    echo "Usage: $0 <service_name>"
    exit 1
fi

SERVICE_NAME="$1"

echo "=== Keyboard Kowboys service-restore ==="
echo "Restoring service: $SERVICE_NAME"
echo ""

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Root privileges required for service management"
    exit 1
fi

# Try systemd first
if command -v systemctl >/dev/null 2>&1; then
    echo "Using systemd to restore service..."

    systemctl unmask "$SERVICE_NAME" 2>/dev/null || true
    systemctl enable "$SERVICE_NAME" 2>/dev/null || true
    systemctl start "$SERVICE_NAME" 2>/dev/null || true

    # Check status
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "Service $SERVICE_NAME restored and running (systemd)"
    else
        echo "Service $SERVICE_NAME unmasked and enabled, but failed to start"
        echo "Check status with: systemctl status $SERVICE_NAME"
        exit 1
    fi

# Try init.d
elif [ -f "/etc/init.d/$SERVICE_NAME" ]; then
    echo "Using init.d to restore service..."

    # Try to enable using available tools
    if command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d "$SERVICE_NAME" enable 2>/dev/null || true
    elif command -v chkconfig >/dev/null 2>&1; then
        chkconfig "$SERVICE_NAME" on 2>/dev/null || true
    fi

    /etc/init.d/"$SERVICE_NAME" start 2>/dev/null || true

    # Check if running
    if /etc/init.d/"$SERVICE_NAME" status >/dev/null 2>&1; then
        echo "Service $SERVICE_NAME restored and running (init.d)"
    else
        echo "Service $SERVICE_NAME enabled, but may not be running"
        echo "Check status with: /etc/init.d/$SERVICE_NAME status"
    fi

# Try BSD-style service command
elif command -v service >/dev/null 2>&1; then
    echo "Using service command to restore service..."
    service "$SERVICE_NAME" start 2>/dev/null || true

    # Check if running
    if service "$SERVICE_NAME" status >/dev/null 2>&1; then
        echo "Service $SERVICE_NAME restored and running (service command)"
    else
        echo "Service $SERVICE_NAME may not be running"
        echo "Check status with: service $SERVICE_NAME status"
    fi

else
    echo "ERROR: No supported service management system found"
    echo "Tried: systemctl, /etc/init.d, service command"
    exit 1
fi

echo ""
echo "Service $SERVICE_NAME has been restored"
