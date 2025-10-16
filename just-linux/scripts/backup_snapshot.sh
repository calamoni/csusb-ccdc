#!/bin/sh
# Create named backup snapshot for easy reference
# Usage: backup_snapshot.sh <name>

set -e

if [ $# -ne 1 ]; then
    echo "ERROR: Missing snapshot name"
    echo "Usage: $0 <name>"
    exit 1
fi

SNAPSHOT_NAME_SUFFIX="$1"
BASE_DIR="${KK_BASE_DIR:-/opt/keyboard_kowboys}"
BACKUP_DIR="${KK_BACKUP_DIR:-$BASE_DIR/backups}"
SCRIPTS_DIR="${KK_SCRIPTS_DIR:-$BASE_DIR/scripts}"

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Root privileges required for backup operations"
    exit 1
fi

echo "=== Creating Named Backup Snapshot: $SNAPSHOT_NAME_SUFFIX ==="

# Create timestamped backup with custom name
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
HOSTNAME=$(hostname)
SNAPSHOT_NAME="all-$HOSTNAME-$TIMESTAMP-$SNAPSHOT_NAME_SUFFIX"
SNAPSHOT_DIR="$BACKUP_DIR/all/$SNAPSHOT_NAME"

echo "Creating snapshot: $SNAPSHOT_NAME"
echo ""

# Run backup
"$SCRIPTS_DIR/backup.sh" -v all "$SNAPSHOT_DIR"

# Create symlink for easy access
ln -sfn "$SNAPSHOT_NAME" "$BACKUP_DIR/all/$SNAPSHOT_NAME_SUFFIX"

echo ""
echo "========================================="
echo "Snapshot created successfully!"
echo "========================================="
echo ""
echo "Location: $SNAPSHOT_DIR"
echo "Symlink:  $BACKUP_DIR/all/$SNAPSHOT_NAME_SUFFIX"
echo ""
echo "To restore from this snapshot:"
echo "  just restore-quick all $SNAPSHOT_NAME_SUFFIX"
echo ""
echo "Or manually:"
echo "  rsync -a $SNAPSHOT_DIR/etc/ /etc/"
