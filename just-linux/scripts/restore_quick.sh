#!/bin/sh
# Quick restore from backup (no safety checks)
# Usage: restore_quick.sh <type> [date]

set -e

if [ $# -lt 1 ]; then
    echo "ERROR: Missing restore type"
    echo "Usage: $0 <type> [date]"
    echo "Types: network, firewall, services, ssh, web, database, all"
    exit 1
fi

RESTORE_TYPE="$1"
RESTORE_DATE="${2:-latest}"

BASE_DIR="${KK_BASE_DIR:-/opt/keyboard_kowboys}"
BACKUP_DIR="${KK_BACKUP_DIR:-$BASE_DIR/backups}"

echo "=== Quick Restore: $RESTORE_TYPE ==="
echo ""

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Root privileges required for restore operations"
    exit 1
fi

# Determine backup source
BACKUP_SOURCE="$BACKUP_DIR/$RESTORE_TYPE/$RESTORE_DATE"

# Check if backup exists
if [ ! -d "$BACKUP_SOURCE" ]; then
    echo "ERROR: Backup not found at: $BACKUP_SOURCE"
    echo ""
    echo "Available backups for $RESTORE_TYPE:"
    ls -1 "$BACKUP_DIR/$RESTORE_TYPE/" 2>/dev/null || echo "  (none)"
    exit 1
fi

# Show warning based on type
case "$RESTORE_TYPE" in
    network)
        echo "⚠️  WARNING: Restoring network may disconnect your session!"
        echo "   Ensure console/physical access is available."
        ;;
    ssh)
        echo "⚠️  WARNING: Restoring SSH may lock you out!"
        echo "   Ensure console/physical access is available."
        ;;
    firewall)
        echo "⚠️  WARNING: Restoring firewall may affect connectivity."
        ;;
esac

echo ""
echo "Restoring $RESTORE_TYPE from: $BACKUP_SOURCE"
echo "Press Ctrl+C within 5 seconds to abort..."
sleep 5

echo ""
echo "Restoring files..."

# Restore based on type
case "$RESTORE_TYPE" in
    network)
        rsync -a "$BACKUP_SOURCE/etc/" /etc/
        echo "Restarting networking..."
        systemctl restart networking 2>/dev/null || systemctl restart NetworkManager 2>/dev/null || /etc/init.d/networking restart 2>/dev/null || true
        ;;

    firewall)
        rsync -a "$BACKUP_SOURCE/etc/" /etc/
        echo "Reloading firewall..."
        if [ -f /etc/iptables/rules.v4 ]; then
            iptables-restore < /etc/iptables/rules.v4 2>/dev/null || true
        fi
        if [ -f /etc/nftables.conf ] && command -v nft >/dev/null 2>&1; then
            nft -f /etc/nftables.conf 2>/dev/null || true
        fi
        if command -v ufw >/dev/null 2>&1; then
            ufw reload 2>/dev/null || true
        fi
        if command -v firewall-cmd >/dev/null 2>&1; then
            firewall-cmd --reload 2>/dev/null || true
        fi
        ;;

    services)
        rsync -a "$BACKUP_SOURCE/etc/" /etc/
        echo "Reloading systemd daemon..."
        systemctl daemon-reload 2>/dev/null || true
        ;;

    ssh)
        rsync -a "$BACKUP_SOURCE/etc/ssh/" /etc/ssh/
        echo "Restarting SSH..."
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || /etc/init.d/ssh restart 2>/dev/null || true
        ;;

    web)
        rsync -a "$BACKUP_SOURCE/etc/" /etc/
        rsync -a "$BACKUP_SOURCE/var/www/" /var/www/ 2>/dev/null || true
        echo "Restarting web servers..."
        systemctl restart nginx 2>/dev/null || /etc/init.d/nginx restart 2>/dev/null || true
        systemctl restart apache2 2>/dev/null || systemctl restart httpd 2>/dev/null || /etc/init.d/apache2 restart 2>/dev/null || true
        ;;

    database)
        rsync -a "$BACKUP_SOURCE/etc/" /etc/
        echo "Restarting database services..."
        systemctl restart mysql 2>/dev/null || systemctl restart mariadb 2>/dev/null || /etc/init.d/mysql restart 2>/dev/null || true
        systemctl restart postgresql 2>/dev/null || /etc/init.d/postgresql restart 2>/dev/null || true
        ;;

    all)
        rsync -a "$BACKUP_SOURCE/etc/" /etc/
        echo "Files restored. Consider rebooting for complete restore."
        ;;

    *)
        echo "ERROR: Unknown restore type: $RESTORE_TYPE"
        echo "Valid types: network, firewall, services, ssh, web, database, all"
        exit 1
        ;;
esac

echo ""
echo "========================================="
echo "Restore complete!"
echo "========================================="
echo ""
echo "Restored from: $BACKUP_SOURCE"
echo ""
echo "Verify system is working correctly!"
