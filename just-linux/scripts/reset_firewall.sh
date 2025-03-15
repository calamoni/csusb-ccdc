#!/bin/sh
# Script to reset firewall to a known-good state
# Supports iptables, nftables, and ufw

set -e

echo "=== Resetting Firewall to Known-Good State ==="
echo "Started at $(date)"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to save current firewall rules for backup
backup_current_rules() {
    BACKUP_DIR="/opt/keyboard_kowboys/backups/firewall"
    mkdir -p "$BACKUP_DIR"
    DATE_STAMP=$(date +%Y%m%d-%H%M%S)
    
    echo "Backing up current firewall rules..."
    
    # Backup iptables rules if available
    if command_exists iptables-save; then
        iptables-save > "$BACKUP_DIR/iptables-${DATE_STAMP}.rules"
        echo "iptables rules backed up to $BACKUP_DIR/iptables-${DATE_STAMP}.rules"
    fi
    
    # Backup nftables rules if available
    if command_exists nft; then
        nft list ruleset > "$BACKUP_DIR/nftables-${DATE_STAMP}.rules"
        echo "nftables rules backed up to $BACKUP_DIR/nftables-${DATE_STAMP}.rules"
    fi
    
    # Backup ufw rules if available
    if command_exists ufw; then
        ufw status verbose > "$BACKUP_DIR/ufw-status-${DATE_STAMP}.txt"
        echo "ufw status backed up to $BACKUP_DIR/ufw-status-${DATE_STAMP}.txt"
    fi
}

# Detect firewall system in use
detect_firewall() {
    if command_exists ufw && ufw status >/dev/null 2>&1; then
        echo "UFW firewall detected"
        FIREWALL="ufw"
    elif command_exists nft && nft list tables >/dev/null 2>&1; then
        echo "nftables firewall detected"
        FIREWALL="nftables"
    elif command_exists iptables; then
        echo "iptables firewall detected"
        FIREWALL="iptables"
    else
        echo "No supported firewall detected"
        FIREWALL="none"
    fi
}

# Reset ufw to a known-good state
reset_ufw() {
    echo "Resetting UFW firewall..."
    
    # Disable first to avoid getting locked out during reset
    ufw disable
    
    # Reset to default
    ufw reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (change port if your SSH runs on a different port)
    ufw allow 22/tcp
    
    # Enable firewall
    ufw enable
    
    # Show status
    ufw status verbose
    
    echo "UFW firewall reset to known-good state"
}

# Reset nftables to a known-good state
reset_nftables() {
    echo "Resetting nftables firewall..."
    
    # Flush all rules
    nft flush ruleset
    
    # Create a basic ruleset
    nft -f - << 'EOF'
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        
        # Allow established and related connections
        ct state established,related accept
        
        # Allow loopback traffic
        iif lo accept
        
        # Allow ICMP and IGMP
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        
        # Allow SSH
        tcp dport 22 accept
        
        # Reject all other traffic
        reject with icmpx type port-unreachable
    }
    
    chain forward {
        type filter hook forward priority 0; policy drop;
    }
    
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
    
    # Show loaded ruleset
    nft list ruleset
    
    echo "nftables firewall reset to known-good state"
}

# Reset iptables to a known-good state
reset_iptables() {
    echo "Resetting iptables firewall..."
    
    # Flush existing rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    
    # Set default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    # Allow loopback traffic
    iptables -A INPUT -i lo -j ACCEPT
    
    # Allow established and related connections
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # Allow SSH (change port if your SSH runs on a different port)
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    # Allow ICMP
    iptables -A INPUT -p icmp -j ACCEPT
    
    # Show rules
    iptables -L -v
    
    # Save rules if possible
    if command_exists iptables-save; then
        if [ -d "/etc/iptables" ]; then
            iptables-save > /etc/iptables/rules.v4
            echo "Rules saved to /etc/iptables/rules.v4"
        elif [ -d "/etc/sysconfig" ]; then
            iptables-save > /etc/sysconfig/iptables
            echo "Rules saved to /etc/sysconfig/iptables"
        fi
    else
        echo "Warning: iptables-save command not found, rules not saved persistently"
    fi
    
    echo "iptables firewall reset to known-good state"
}

# Main firewall reset logic
echo "Detecting current firewall system..."
detect_firewall

# Backup current rules before making changes
backup_current_rules

# Reset based on detected firewall
case "$FIREWALL" in
    "ufw")
        reset_ufw
        ;;
    "nftables")
        reset_nftables
        ;;
    "iptables")
        reset_iptables
        ;;
    "none")
        echo "No firewall detected. Setting up iptables as default..."
        reset_iptables
        ;;
    *)
        echo "Error: Unknown firewall type: $FIREWALL"
        exit 1
        ;;
esac

echo "=== Firewall Reset Complete ==="
echo "Completed at $(date)"
exit 0
