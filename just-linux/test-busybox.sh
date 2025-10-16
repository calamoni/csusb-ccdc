#!/bin/sh
# BusyBox Container Test Environment
# Tests the backup script in a minimal BusyBox environment

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="keyboard-kowboys-busybox-test"

echo "=== Keyboard Kowboys BusyBox Test Environment ==="
echo ""

# Check if Docker is available
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker is not installed or not in PATH"
    echo "Please install Docker first:"
    echo "  - Debian/Ubuntu: sudo apt-get install docker.io"
    echo "  - RHEL/CentOS: sudo yum install docker"
    echo "  - Or use: just install-docker"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running"
    echo "Start it with: sudo systemctl start docker"
    exit 1
fi

# Clean up any existing test container
echo "Cleaning up any existing test containers..."
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo ""
echo "Starting BusyBox container with mounted scripts..."
echo "Container name: $CONTAINER_NAME"
echo "Mounted directory: $SCRIPT_DIR -> /test"
echo ""

# Create temporary directory for writable workspace
TEMP_WORKSPACE=$(mktemp -d)
echo "Created temporary workspace: $TEMP_WORKSPACE"
echo "Note: Files saved to /workspace will be available at: $TEMP_WORKSPACE"
echo ""

# Cleanup function (optional - commented out to keep files)
# cleanup() {
#     echo ""
#     echo "Cleaning up temporary workspace..."
#     rm -rf "$TEMP_WORKSPACE"
# }
# trap cleanup EXIT

# Keep workspace after exit
echo "Workspace will persist after exit for review"

# Run BusyBox container with:
# - Interactive terminal
# - Scripts mounted read-only to /test
# - Writable workspace at /workspace
# - tmpfs for /tmp and /opt
# - Privileged mode (for testing backup operations)
docker run -it --rm \
    --name "$CONTAINER_NAME" \
    --privileged \
    -v "$SCRIPT_DIR:/test:ro" \
    -v "$TEMP_WORKSPACE:/workspace" \
    --tmpfs /tmp:rw,exec,nosuid,size=512m \
    --tmpfs /opt:rw,exec,nosuid,size=256m \
    -w /workspace \
    busybox:latest \
    /bin/sh -c '
echo "=== BusyBox Test Environment Ready ==="
echo ""
echo "Environment Information:"
echo "  BusyBox version: $(busybox | head -1)"
echo "  Shell: $SHELL"
echo "  Working directory: $(pwd)"
echo ""
echo "Writable Filesystems:"
echo "  /workspace - Persistent across session (host-mounted)"
echo "  /tmp       - Temporary storage (tmpfs, 512MB)"
echo "  /opt       - Temporary storage (tmpfs, 256MB)"
echo ""
echo "Available test scripts (read-only):"
ls -la /test/scripts/*.sh 2>/dev/null | head -10
echo ""
echo "=== Quick Setup (Auto) ==="
echo ""
# Auto-setup test environment
echo "Setting up test environment..."
mkdir -p /opt/keyboard_kowboys/scripts
mkdir -p /opt/keyboard_kowboys/backups
mkdir -p /opt/keyboard_kowboys/logs
mkdir -p /opt/keyboard_kowboys/configs
mkdir -p /opt/keyboard_kowboys/playbooks
cp -r /test/scripts/* /opt/keyboard_kowboys/scripts/ 2>/dev/null || true
cp /test/Justfile /opt/keyboard_kowboys/ 2>/dev/null || true
cp /test/ansible.cfg /opt/keyboard_kowboys/ 2>/dev/null || true
cp /test/hosts.ini /opt/keyboard_kowboys/ 2>/dev/null || true
cp -r /test/playbooks/* /opt/keyboard_kowboys/playbooks/ 2>/dev/null || true
chmod +x /opt/keyboard_kowboys/scripts/*.sh 2>/dev/null || true
echo "✓ Test environment created at /opt/keyboard_kowboys"
echo ""
echo "Directory structure:"
ls -la /opt/keyboard_kowboys/
echo ""
echo "Available scripts:"
ls -la /opt/keyboard_kowboys/scripts/ | head -10
echo ""
echo "=== Quick Test Commands ==="
echo ""
echo "NOTE: '\''just'\'' command is not available in BusyBox"
echo "Use scripts directly or install just separately"
echo ""
echo "1. Navigate to working directory:"
echo "   cd /opt/keyboard_kowboys"
echo ""
echo "2. Test backup script syntax:"
echo "   sh -n scripts/backup.sh"
echo ""
echo "3. Check script help:"
echo "   ./scripts/backup.sh --help"
echo ""
echo "4. Run dry-run backup:"
echo "   ./scripts/backup.sh -d -v network /tmp/test-backup"
echo ""
echo "5. Run real backup:"
echo "   ./scripts/backup.sh -v network /tmp/test-backup"
echo ""
echo "6. Verify backup:"
echo "   ls -la /tmp/test-backup/network/latest/"
echo "   cat logs/system-backup.log"
echo ""
echo "7. Test security backup:"
echo "   ./scripts/backup.sh -v security /tmp/test-backup"
echo ""
echo "8. Test SUID binary finding (BusyBox compatibility):"
echo "   find /bin -type f -perm -4000 -exec ls -la {} \\; 2>/dev/null | head -5"
echo ""
echo "9. Save work to /workspace (persists):"
echo "   cp logs/system-backup.log /workspace/"
echo ""
echo "10. View Justfile (reference):"
echo "    cat Justfile | head -50"
echo ""
echo "=== Notes ==="
echo "- Scripts in /test are read-only (your source code)"
echo "- Working copy in /opt/keyboard_kowboys (writable tmpfs)"
echo "- Justfile is copied for reference (just not installed)"
echo "- Use /workspace to save files to host"
echo "- BusyBox has limited tools - script has fallbacks"
echo "- Run scripts directly: ./scripts/backup.sh"
echo "- Type '\''exit'\'' to leave container"
echo ""
echo "=== Environment Variables ==="
export KK_BASE_DIR="/opt/keyboard_kowboys"
export KK_CONFIG_DIR="/opt/keyboard_kowboys/configs"
export KK_LOG_DIR="/opt/keyboard_kowboys/logs"
export KK_BACKUP_DIR="/opt/keyboard_kowboys/backups"
echo "  KK_BASE_DIR=$KK_BASE_DIR"
echo "  KK_CONFIG_DIR=$KK_CONFIG_DIR"
echo "  KK_LOG_DIR=$KK_LOG_DIR"
echo "  KK_BACKUP_DIR=$KK_BACKUP_DIR"
echo ""
echo "=== Shell Ready ==="
echo ""
exec /bin/sh
'

echo ""
echo "Container exited."
echo ""
echo "=== Workspace Location ==="
echo "Files saved to /workspace are available at:"
echo "  $TEMP_WORKSPACE"
echo ""
echo "To clean up manually:"
echo "  rm -rf $TEMP_WORKSPACE"
echo ""
