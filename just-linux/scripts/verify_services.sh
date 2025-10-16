#!/bin/sh

set -e

# Check if critical_only parameter was provided
if [ $# -ge 1 ]; then
    CRITICAL_ONLY="$1"
else
    CRITICAL_ONLY="false"
fi

echo "=== Service Integrity Verification ==="
echo "Started at $(date)"
echo "Critical services only: $CRITICAL_ONLY"
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Define critical services - adjust based on your system requirements
CRITICAL_SERVICES="sshd systemd-journald systemd-logind cron"

# Additional services to check when not in critical_only mode
if [ "$CRITICAL_ONLY" != "true" ]; then
    # Add more services here
    ALL_SERVICES="$CRITICAL_SERVICES rsyslog networking network-manager apache2 nginx mysql postgresql"
else
    ALL_SERVICES="$CRITICAL_SERVICES"
fi

# Check service status using systemctl if available
if command_exists systemctl; then
    echo "=== Systemd Service Status ==="
    for service in $ALL_SERVICES; do
        echo "Checking $service:"
        if systemctl list-unit-files --type=service | grep -q "$service"; then
            # Service exists, check its status
            systemctl status "$service" --no-pager || echo "Service $service is not running correctly"
            
            # Check if service has been modified since installation
            if command_exists debsums && [ -f "/lib/systemd/system/$service.service" ]; then
                echo "Verifying $service binary integrity:"
                debsums -s "/lib/systemd/system/$service.service" 2>/dev/null || echo "Warning: $service service file may have been modified"
            fi
            
            # Check service configuration if it exists
            if [ -f "/etc/$service/$service.conf" ]; then
                echo "Service configuration found at /etc/$service/$service.conf"
            elif [ -f "/etc/$service.conf" ]; then
                echo "Service configuration found at /etc/$service.conf"
            fi
        else
            echo "Service $service not found on the system"
        fi
        echo ""
    done
# If systemctl is not available, try legacy service command
elif command_exists service; then
    echo "=== Legacy Service Status ==="
    for service in $ALL_SERVICES; do
        echo "Checking $service:"
        service "$service" status || echo "Service $service is not running correctly"
        
        # Check service file if it exists
        if [ -f "/etc/init.d/$service" ]; then
            echo "Init script found at /etc/init.d/$service"
            # Check file permissions
            ls -la "/etc/init.d/$service"
        fi
        echo ""
    done
else
    echo "Error: No service management command found (systemctl or service)"
    exit 1
fi

# Check for unusual services or ones not from the package manager
echo "=== Checking for Unusual Services ==="
if command_exists systemctl; then
    # Get all enabled services
    ENABLED_SERVICES=$(systemctl list-unit-files --state=enabled --type=service | grep "\.service" | awk '{print $1}')
    
    echo "Enabled services not from package manager:"
    for service in $ENABLED_SERVICES; do
        # Strip .service suffix if present
        service_name=$(echo "$service" | sed 's/\.service$//')
        
        # Check if service is from a package
        if command_exists dpkg && ! dpkg -S "$service_name" >/dev/null 2>&1; then
            if command_exists rpm && ! rpm -qf "/lib/systemd/system/$service" >/dev/null 2>&1; then
                echo "- $service may not be from the package manager"
                systemctl status "$service" --no-pager | head -3
            fi
        fi
    done
fi
echo ""

# Verify service binary integrity if possible
echo "=== Verifying Service Binary Integrity ==="
for service in $ALL_SERVICES; do
    # Find the binary path
    BINARY_PATH=""
    
    # Try different methods to find the service binary
    if command_exists systemctl && systemctl status "$service" >/dev/null 2>&1; then
        BINARY_PATH=$(systemctl show -p ExecStart "$service" 2>/dev/null | grep -o '=[[:graph:]]*' | cut -d'=' -f2)
    elif command_exists ps && ps aux | grep -v grep | grep -q "$service"; then
        BINARY_PATH=$(which "$service" 2>/dev/null)
    fi
    
    if [ -n "$BINARY_PATH" ] && [ -f "$BINARY_PATH" ]; then
        echo "Checking binary integrity for $service ($BINARY_PATH):"
        
        # Check if MD5 verification tools are available
        if command_exists debsums; then
            debsums -s "$BINARY_PATH" 2>/dev/null || echo "Warning: Binary for $service may have been modified"
        elif command_exists rpm; then
            rpm -V $(rpm -qf "$BINARY_PATH" 2>/dev/null) || echo "Warning: Binary for $service may have been modified"
        else
            # If no verification tool is available, at least check file attributes
            echo "File attributes:"
            ls -la "$BINARY_PATH"
            
            # Check for strange permissions
            if [ "$(stat -c '%a' "$BINARY_PATH")" != "755" ]; then
                echo "Warning: Unusual permissions on $BINARY_PATH"
            fi
        fi
    else
        echo "Could not determine binary path for $service"
    fi
    echo ""
done

# Check system startup (e.g., systemd) integrity
if [ -d "/lib/systemd/system" ]; then
    echo "=== Checking systemd Integrity ==="
    ls -la /lib/systemd/system/sysinit.target
    echo "Systemd targets:"
    ls -la /lib/systemd/system/*.target | head -5
    echo "(showing first 5 targets only)"
    echo ""
fi

# Check for any unexpected changes to the service configurations
echo "=== Checking for Recent Service Configuration Changes ==="
if command_exists fd; then
    echo "Files in /etc/systemd modified in the last 7 days:"
    fd --type f --changed-within 7d --base-directory /etc/systemd --exec ls -la 2>/dev/null || echo "No recent changes found"

    echo "Files in /etc/init.d modified in the last 7 days:"
    fd --type f --changed-within 7d --base-directory /etc/init.d --exec ls -la 2>/dev/null || echo "No recent changes found"
elif command_exists find; then
    echo "Files in /etc/systemd modified in the last 7 days:"
    find /etc/systemd -type f -mtime -7 -ls 2>/dev/null || echo "No recent changes found"

    echo "Files in /etc/init.d modified in the last 7 days:"
    find /etc/init.d -type f -mtime -7 -ls 2>/dev/null || echo "No recent changes found"
else
    echo "find command not available, skipping recent changes check"
fi
echo ""

# Check for any services listening on unusual ports
echo "=== Services Listening on Network Ports ==="
if command_exists ss; then
    ss -tulpn | sort -n -k 5
elif command_exists netstat; then
    netstat -tulpn | sort -n -k 4
else
    echo "Neither ss nor netstat command available, skipping network port check"
fi

echo ""
echo "=== Service Verification Complete ==="
echo "Completed at $(date)"
exit 0
