#!/bin/sh
# Script to backup system configurations
# Usage: backup.sh [system_name] [backup_directory]

set -e

# Check if required arguments are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 [system_name] [backup_directory]"
    exit 1
fi

SYSTEM_NAME="$1"
BACKUP_DIR="$2"
DATE_STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${SYSTEM_NAME}-${DATE_STAMP}"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_PATH"

# Log backup start
echo "Starting backup of $SYSTEM_NAME at $(date)"

# Backup based on system name
case "$SYSTEM_NAME" in
    "all")
        # Backup important configuration files
        echo "Backing up system configurations..."
        tar -czf "${BACKUP_PATH}/etc.tar.gz" /etc 2>/dev/null || echo "Warning: Some files in /etc could not be backed up"
        
        # Backup user configuration files
        echo "Backing up user configurations..."
        tar -czf "${BACKUP_PATH}/home-configs.tar.gz" /home/*/.??* 2>/dev/null || echo "Warning: Some user config files could not be backed up"
        
        # Generate MD5 checksums of critical binaries
        echo "Creating binary checksums..."
        find /bin /sbin /usr/bin -type f -exec md5sum {} \; > "${BACKUP_PATH}/binaries.md5" 2>/dev/null
        
        # Copy to main backup dir for reference in integrity checks
        cp "${BACKUP_PATH}/binaries.md5" "${BACKUP_DIR}/binaries.md5"
        
        # Save currently installed packages
        if command -v dpkg >/dev/null 2>&1; then
            dpkg --get-selections > "${BACKUP_PATH}/packages.list"
        elif command -v rpm >/dev/null 2>&1; then
            rpm -qa > "${BACKUP_PATH}/packages.list"
        else
            echo "Warning: Package manager not recognized, skipping package list backup"
        fi
        
        # Save list of active services
        if command -v systemctl >/dev/null 2>&1; then
            systemctl list-units --type=service --state=active > "${BACKUP_PATH}/active_services.list"
        else
            echo "Warning: systemd not detected, skipping service list backup"
        fi
        ;;
        
    "network")
        # Backup network configurations
        echo "Backing up network configurations..."
        mkdir -p "${BACKUP_PATH}/network"
        cp -a /etc/network "${BACKUP_PATH}/network/" 2>/dev/null || echo "Warning: /etc/network not found"
        cp -a /etc/netplan "${BACKUP_PATH}/network/" 2>/dev/null || echo "Warning: /etc/netplan not found"
        cp /etc/hosts "${BACKUP_PATH}/network/" 2>/dev/null || echo "Warning: /etc/hosts not found"
        cp /etc/resolv.conf "${BACKUP_PATH}/network/" 2>/dev/null || echo "Warning: /etc/resolv.conf not found"
        
        # Save network interfaces and routing tables
        ip addr > "${BACKUP_PATH}/network/ip_addr.txt"
        ip route > "${BACKUP_PATH}/network/ip_route.txt"
        ;;
        
    "firewall")
        # Backup firewall rules
        echo "Backing up firewall configurations..."
        mkdir -p "${BACKUP_PATH}/firewall"
        
        # Try iptables backup
        if command -v iptables-save >/dev/null 2>&1; then
            iptables-save > "${BACKUP_PATH}/firewall/iptables.rules"
        fi
        
        # Try nftables backup
        if command -v nft >/dev/null 2>&1; then
            nft list ruleset > "${BACKUP_PATH}/firewall/nftables.rules"
        fi
        
        # Try ufw backup
        if command -v ufw >/dev/null 2>&1; then
            ufw status verbose > "${BACKUP_PATH}/firewall/ufw_status.txt"
        fi
        ;;
        
    "services")
        # Backup service configurations
        echo "Backing up service configurations..."
        
        # If systemd is present
        if command -v systemctl >/dev/null 2>&1; then
            mkdir -p "${BACKUP_PATH}/systemd"
            cp -a /etc/systemd "${BACKUP_PATH}/systemd/"
            systemctl list-units --type=service > "${BACKUP_PATH}/systemd/services_list.txt"
        fi
        
        # Backup other init systems if present
        if [ -d "/etc/init.d" ]; then
            mkdir -p "${BACKUP_PATH}/init.d"
            cp -a /etc/init.d "${BACKUP_PATH}/init.d/"
        fi
        ;;
        
    *)
        echo "Backing up specific system: $SYSTEM_NAME"
        # Try to backup config files related to the specified system
        if [ -d "/etc/$SYSTEM_NAME" ]; then
            mkdir -p "${BACKUP_PATH}/etc"
            cp -a "/etc/$SYSTEM_NAME" "${BACKUP_PATH}/etc/"
            echo "Backed up /etc/$SYSTEM_NAME"
        else
            echo "Warning: No configuration found for $SYSTEM_NAME in /etc"
        fi
        
        # Try to backup service files if they exist
        if [ -f "/etc/systemd/system/$SYSTEM_NAME.service" ]; then
            mkdir -p "${BACKUP_PATH}/systemd/system"
            cp "/etc/systemd/system/$SYSTEM_NAME.service" "${BACKUP_PATH}/systemd/system/"
            echo "Backed up $SYSTEM_NAME systemd service file"
        fi
        ;;
esac

# Create a backup manifest
echo "Backup created: $DATE_STAMP" > "${BACKUP_PATH}/manifest.txt"
echo "System: $SYSTEM_NAME" >> "${BACKUP_PATH}/manifest.txt"
echo "Contents:" >> "${BACKUP_PATH}/manifest.txt"
find "$BACKUP_PATH" -type f | grep -v "manifest.txt" >> "${BACKUP_PATH}/manifest.txt"

echo "Backup completed successfully to $BACKUP_PATH"
exit 0
