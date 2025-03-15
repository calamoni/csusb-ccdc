#!/bin/sh
# Script to update all security tools in the Keyboard Kowboys toolkit
# This script detects and updates tools from various package managers

set -e

BASE_DIR="/opt/keyboard_kowboys"
TOOLS_DIR="$BASE_DIR/tools"
LOG_DIR="$BASE_DIR/logs"

echo "=== Updating Keyboard Kowboys Tools ==="
echo "Started at $(date)"
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"
UPDATE_LOG="$LOG_DIR/update_$(date +%Y%m%d).log"

# Log both to stdout and the log file
log() {
    echo "$1"
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" >> "$UPDATE_LOG"
}

# Update system packages
update_system_packages() {
    log "Updating system packages..."
    
    if command_exists apt-get; then
        log "Detected Debian/Ubuntu system"
        apt-get update >> "$UPDATE_LOG" 2>&1
        apt-get upgrade -y >> "$UPDATE_LOG" 2>&1
        apt-get autoremove -y >> "$UPDATE_LOG" 2>&1
        apt-get clean >> "$UPDATE_LOG" 2>&1
    elif command_exists yum; then
        log "Detected RHEL/CentOS system"
        yum update -y >> "$UPDATE_LOG" 2>&1
        yum clean all >> "$UPDATE_LOG" 2>&1
    elif command_exists dnf; then
        log "Detected Fedora/newer RHEL system"
        dnf update -y >> "$UPDATE_LOG" 2>&1
        dnf clean all >> "$UPDATE_LOG" 2>&1
    elif command_exists zypper; then
        log "Detected openSUSE system"
        zypper update -y >> "$UPDATE_LOG" 2>&1
        zypper clean >> "$UPDATE_LOG" 2>&1
    elif command_exists pacman; then
        log "Detected Arch Linux system"
        pacman -Syu --noconfirm >> "$UPDATE_LOG" 2>&1
        pacman -Sc --noconfirm >> "$UPDATE_LOG" 2>&1
    else
        log "Warning: No supported package manager found"
        return 1
    fi
    
    log "System packages updated successfully"
    return 0
}

# Update Python packages
update_python_packages() {
    log "Updating Python packages..."
    
    if command_exists pip3; then
        log "Updating pip3 packages..."
        pip3 list --outdated --format=freeze | cut -d = -f 1 | xargs -r pip3 install --upgrade >> "$UPDATE_LOG" 2>&1
    elif command_exists pip; then
        log "Updating pip packages..."
        pip list --outdated --format=freeze | cut -d = -f 1 | xargs -r pip install --upgrade >> "$UPDATE_LOG" 2>&1
    else
        log "Warning: pip not found, skipping Python package updates"
        return 1
    fi
    
    log "Python packages updated successfully"
    return 0
}

# Update Ruby gems
update_ruby_gems() {
    log "Updating Ruby gems..."
    
    if command_exists gem; then
        gem update --system >> "$UPDATE_LOG" 2>&1
        gem update >> "$UPDATE_LOG" 2>&1
    else
        log "Warning: gem not found, skipping Ruby gem updates"
        return 1
    fi
    
    log "Ruby gems updated successfully"
    return 0
}

# Update Node.js packages
update_node_packages() {
    log "Updating Node.js packages..."
    
    if command_exists npm; then
        log "Updating global npm packages..."
        npm update -g >> "$UPDATE_LOG" 2>&1
    else
        log "Warning: npm not found, skipping Node.js package updates"
        return 1
    fi
    
    log "Node.js packages updated successfully"
    return 0
}

# Update Go packages
update_go_packages() {
    log "Updating Go packages..."
    
    if command_exists go; then
        # This is a simplified approach - in reality, updating Go packages
        # would require more specific handling for each package
        log "Go is installed, but package updates need to be handled manually"
        return 0
    else
        log "Warning: go not found, skipping Go package updates"
        return 1
    fi
    
    return 0
}

# Update custom tools in the tools directory
update_custom_tools() {
    log "Updating custom tools in $TOOLS_DIR..."
    
    # Create tools directory if it doesn't exist
    mkdir -p "$TOOLS_DIR"
    
    # Process each subdirectory in the tools directory
    if [ -d "$TOOLS_DIR" ]; then
        for tool_dir in "$TOOLS_DIR"/*; do
            if [ -d "$tool_dir" ] && [ -d "$tool_dir/.git" ]; then
                tool_name=$(basename "$tool_dir")
                log "Updating $tool_name from git repository..."
                
                # Store current directory
                CURRENT_DIR=$(pwd)
                
                # Change to tool directory and update
                cd "$tool_dir"
                git pull >> "$UPDATE_LOG" 2>&1
                
                # Change back to previous directory
                cd "$CURRENT_DIR"
                
                log "$tool_name updated successfully"
            elif [ -d "$tool_dir" ]; then
                tool_name=$(basename "$tool_dir")
                log "Directory $tool_name is not a git repository, skipping"
            fi
        done
    else
        log "Warning: $TOOLS_DIR does not exist or is not a directory"
    fi
    
    return 0
}

# Check for and install Chimera if not present
check_install_chimera() {
    CHIMERA_DIR="$BASE_DIR/ops/chimera"
    
    if [ ! -d "$CHIMERA_DIR" ]; then
        log "Chimera not found, installing..."
        mkdir -p "$BASE_DIR/ops"
        
        if command_exists git; then
            git clone https://github.com/tokyoneon/Chimera.git "$CHIMERA_DIR" >> "$UPDATE_LOG" 2>&1
            log "Chimera installed successfully"
        else
            log "Error: git command not found, cannot install Chimera"
            return 1
        fi
    else
        log "Chimera already installed, updating..."
        
        # Store current directory
        CURRENT_DIR=$(pwd)
        
        # Change to Chimera directory and update
        cd "$CHIMERA_DIR"
        git pull >> "$UPDATE_LOG" 2>&1
        
        # Change back to previous directory
        cd "$CURRENT_DIR"
        
        log "Chimera updated successfully"
    fi
    
    return 0
}

# Main update process
log "Starting update process..."

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    log "Error: This script requires root privileges"
    exit 1
fi

# Update system packages
update_system_packages
echo ""

# Update Python packages
update_python_packages
echo ""

# Update Ruby gems
update_ruby_gems
echo ""

# Update Node.js packages
update_node_packages
echo ""

# Update Go packages
update_go_packages
echo ""

# Update custom tools
update_custom_tools
echo ""

# Check and install/update Chimera
check_install_chimera
echo ""

log "=== Update Complete ==="
log "All tools and packages have been updated"
log "Update log saved to $UPDATE_LOG"
echo ""
echo "Update completed at $(date)"
exit 0
