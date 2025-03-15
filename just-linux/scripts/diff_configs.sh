#!/bin/sh

set -e

# Check if required arguments are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 [system_name] [backup_directory]"
    exit 1
fi

SYSTEM_NAME="$1"
BACKUP_DIR="$2"

# Find the latest backup for the given system
latest_backup=$(find "$BACKUP_DIR" -maxdepth 1 -name "${SYSTEM_NAME}-*" -type d | sort -r | head -n 1)

if [ -z "$latest_backup" ]; then
    echo "Error: No backup found for $SYSTEM_NAME in $BACKUP_DIR"
    exit 1
fi

echo "Using latest backup: $latest_backup"

# Create temporary directory for current configs
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Function to compare files with diff
compare_files() {
    local file1="$1"
    local file2="$2"
    local label="$3"
    
    if [ ! -f "$file1" ] || [ ! -f "$file2" ]; then
        echo "Cannot compare $label: One of the files does not exist"
        return 1
    fi
    
    echo "=== Comparing $label ==="
    diff -u "$file1" "$file2" || echo "Differences found in $label"
    echo ""
}

# Function to extract from tar and compare
compare_from_tar() {
    local tar_file="$1"
    local extract_path="$2"
    local current_path="$3"
    local label="$4"
    
    if [ ! -f "$tar_file" ]; then
        echo "Cannot compare $label: Backup archive not found"
        return 1
    fi
    
    mkdir -p "$TEMP_DIR/extract"

    # Try extraction with and without leading slash
    tar -xzf "$tar_file" -C "$TEMP_DIR/extract" "$extract_path" 2>/dev/null || 
    tar -xzf "$tar_file" -C "$TEMP_DIR/extract" "${extract_path#/}" 2>/dev/null ||
    {
       echo "Cannot extract $extract_path from backup archive"
       return 1
    } 
    echo "=== Comparing $label ==="
    if [ -d "$current_path" ] && [ -d "$TEMP_DIR/extract$extract_path" ]; then
        diff -ur "$TEMP_DIR/extract$extract_path" "$current_path" || echo "Differences found in $label directory"
    elif [ -f "$current_path" ] && [ -f "$TEMP_DIR/extract$extract_path" ]; then
        diff -u "$TEMP_DIR/extract$extract_path" "$current_path" || echo "Differences found in $label file"
    else
        echo "Cannot compare: File types don't match or files don't exist"
    fi
    echo ""
    
    rm -rf "$TEMP_DIR/extract"
}

# Perform comparison based on system name
case "$SYSTEM_NAME" in
    "all")
        # Compare binary checksums
        echo "Checking binary integrity..."
        if [ -f "${latest_backup}/binaries.md5" ]; then
            # Create current checksums
            find /bin /sbin /usr/bin -type f -exec md5sum {} \; > "$TEMP_DIR/current_binaries.md5" 2>/dev/null
            
            # Use grep to find differences
            echo "Binary files with different checksums:"
            grep -F -vf "${latest_backup}/binaries.md5" "$TEMP_DIR/current_binaries.md5" || echo "No checksum differences found"
            echo "New binary files (not in backup):"
            grep -F -vf "$TEMP_DIR/current_binaries.md5" "${latest_backup}/binaries.md5" || echo "No new binary files found"
        else
            echo "Warning: No binary checksums found in backup"
        fi
        
        # Compare etc configurations
        if [ -f "${latest_backup}/etc.tar.gz" ]; then
            # Extract important config files to compare
            for config_file in passwd group shadow; do
                compare_from_tar "${latest_backup}/etc.tar.gz" "/etc/$config_file" "/etc/$config_file" "System $config_file file"
            done
        fi
        
        # Compare installed packages
        if [ -f "${latest_backup}/packages.list" ]; then
            # Create current package list
            if command -v dpkg >/dev/null 2>&1; then
                dpkg --get-selections > "$TEMP_DIR/current_packages.list"
            elif command -v rpm >/dev/null 2>&1; then
                rpm -qa > "$TEMP_DIR/current_packages.list"
            fi
            
            if [ -f "$TEMP_DIR/current_packages.list" ]; then
                compare_files "${latest_backup}/packages.list" "$TEMP_DIR/current_packages.list" "Installed packages"
            fi
        fi
        
        # Compare active services
        if [ -f "${latest_backup}/active_services.list" ] && command -v systemctl >/dev/null 2>&1; then
            systemctl list-units --type=service --state=active > "$TEMP_DIR/current_services.list"
            compare_files "${latest_backup}/active_services.list" "$TEMP_DIR/current_services.list" "Active services"
        fi
        ;;
        
    "network")
        # Create current network configuration files
        mkdir -p "$TEMP_DIR/network"
        ip addr > "$TEMP_DIR/network/ip_addr.txt"
        ip route > "$TEMP_DIR/network/ip_route.txt"
        
        # Compare network configuration
        if [ -f "${latest_backup}/network/ip_addr.txt" ]; then
            compare_files "${latest_backup}/network/ip_addr.txt" "$TEMP_DIR/network/ip_addr.txt" "Network interfaces"
        fi
        
        if [ -f "${latest_backup}/network/ip_route.txt" ]; then
            compare_files "${latest_backup}/network/ip_route.txt" "$TEMP_DIR/network/ip_route.txt" "Routing tables"
        fi
        
        # Compare network configuration files
        for config_file in hosts resolv.conf; do
            if [ -f "${latest_backup}/network/$config_file" ]; then
                compare_files "${latest_backup}/network/$config_file" "/etc/$config_file" "Network $config_file"
            fi
        done
        ;;
        
    "firewall")
        # Create current firewall rules
        mkdir -p "$TEMP_DIR/firewall"
        
        # Compare iptables rules
        if [ -f "${latest_backup}/firewall/iptables.rules" ] && command -v iptables-save >/dev/null 2>&1; then
            iptables-save > "$TEMP_DIR/firewall/current_iptables.rules"
            compare_files "${latest_backup}/firewall/iptables.rules" "$TEMP_DIR/firewall/current_iptables.rules" "iptables rules"
        fi
        
        # Compare nftables rules
        if [ -f "${latest_backup}/firewall/nftables.rules" ] && command -v nft >/dev/null 2>&1; then
            nft list ruleset > "$TEMP_DIR/firewall/current_nftables.rules"
            compare_files "${latest_backup}/firewall/nftables.rules" "$TEMP_DIR/firewall/current_nftables.rules" "nftables rules"
        fi
        
        # Compare ufw status
        if [ -f "${latest_backup}/firewall/ufw_status.txt" ] && command -v ufw >/dev/null 2>&1; then
            ufw status verbose > "$TEMP_DIR/firewall/current_ufw_status.txt"
            compare_files "${latest_backup}/firewall/ufw_status.txt" "$TEMP_DIR/firewall/current_ufw_status.txt" "UFW status"
        fi
        ;;
        
    "services")
        # Compare systemd configuration
        if [ -d "${latest_backup}/systemd" ] && [ -d "/etc/systemd" ]; then
            echo "=== Comparing systemd configurations ==="
            diff -ur "${latest_backup}/systemd" "/etc/systemd" || echo "Differences found in systemd configuration"
            echo ""
        fi
        
        # Compare service list
        if [ -f "${latest_backup}/systemd/services_list.txt" ] && command -v systemctl >/dev/null 2>&1; then
            systemctl list-units --type=service > "$TEMP_DIR/current_services_list.txt"
            compare_files "${latest_backup}/systemd/services_list.txt" "$TEMP_DIR/current_services_list.txt" "Systemd services"
        fi
        ;;
        
    *)
        # Custom system diff
        echo "Comparing configurations for specific system: $SYSTEM_NAME"
        
        # Check for config in /etc
        if [ -d "${latest_backup}/etc/$SYSTEM_NAME" ] && [ -d "/etc/$SYSTEM_NAME" ]; then
            echo "=== Comparing /etc/$SYSTEM_NAME configuration ==="
            diff -ur "${latest_backup}/etc/$SYSTEM_NAME" "/etc/$SYSTEM_NAME" || echo "Differences found in $SYSTEM_NAME configuration"
            echo ""
        fi
        
        # Check for service file
        if [ -f "${latest_backup}/systemd/system/$SYSTEM_NAME.service" ] && [ -f "/etc/systemd/system/$SYSTEM_NAME.service" ]; then
            compare_files "${latest_backup}/systemd/system/$SYSTEM_NAME.service" "/etc/systemd/system/$SYSTEM_NAME.service" "$SYSTEM_NAME service file"
        fi
        ;;
esac

echo "Configuration comparison completed."
exit 0
