#!/bin/sh
set -e

# Use sh instead of bash for better compatibility with busybox
# Set PATH to include current directory for locally installed binaries
export PATH="$(pwd):$PATH"

# Function to determine system architecture
get_architecture() {
    # Get architecture using uname
    arch=$(uname -m)
    
    # Map architecture names to those used in the static-curl repo
    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        i686|i386)
            echo "i386"
            ;;
        armv7l|armhf)
            echo "armhf"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Function to check if systemd is present
has_systemd() {
    # Check for systemd by looking for systemctl
    if command -v systemctl > /dev/null 2>&1; then
        # Verify systemd is actually running
        if systemctl is-system-running > /dev/null 2>&1 || systemctl is-system-running 2>&1 | grep -q "degraded"; then
            return 0
        fi
    fi
    return 1
}

# Function to check if launchd is present (macOS)
has_launchd() {
    # Check for launchd by looking for launchctl
    if command -v launchctl > /dev/null 2>&1; then
        # Verify launchd is running by getting its PID
        if ps -p 1 -o comm= 2>/dev/null | grep -q "launchd"; then
            return 0
        fi
    fi
    return 1
}

# Check if curl is already installed and working
echo "Checking for curl..."
if ! command -v curl > /dev/null 2>&1 || ! curl --version > /dev/null 2>&1; then
    echo "curl is not installed or not working. Installing..."
    
    # Check if wget is available
    if ! command -v wget > /dev/null 2>&1; then
        echo "Error: Neither curl nor wget is installed. Please install one of them first."
        exit 1
    fi
    
    # Get system architecture
    ARCH=$(get_architecture)
    
    if [ "$ARCH" = "unknown" ]; then
        echo "Error: Could not determine system architecture."
        exit 1
    fi
    
    # Create a temporary directory
    TEMP_DIR=$(mktemp -d)
    CURL_BINARY="$TEMP_DIR/curl"
    
    echo "Downloading curl for $ARCH architecture..."
    # Use --no-check-certificate for BusyBox wget which lacks -k option
    wget --no-check-certificate -q "https://github.com/moparisthebest/static-curl/releases/latest/download/curl-$ARCH" -O "$CURL_BINARY"
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download curl."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Make the binary executable
    chmod +x "$CURL_BINARY"
    
    # In busybox/docker environments, just keep curl in current directory
    cp "$CURL_BINARY" ./curl
    chmod +x ./curl
    echo "curl installed to $(pwd)/curl"
    
    # Clean up temp directory
    rm -rf "$TEMP_DIR"
    
    # Verify installation
    if ! ./curl --version > /dev/null 2>&1; then
        echo "Error: curl installation failed. Cannot continue."
        exit 1
    fi
    
    # Use the local curl for the Nix installation
    CURL_CMD="./curl"
else
    CURL_CMD="curl"
    echo "curl is already installed."
fi

# Detect init system and prepare install options
echo "Detecting init system..."
INSTALL_OPTS="install linux --determinate --no-confirm --init none"

if has_systemd; then
    echo "Detected systemd init system."
    INSTALL_OPTS="install --determinate --no-confirm"
elif has_launchd; then
    echo "Detected launchd init system (macOS)."
    INSTALL_OPTS="install --determinate --no-confirm"
else
    echo "No supported init system detected. Using --init none option."
fi

# Download the nix-installer binary directly instead of using the curl|sh method
echo "Downloading nix-installer binary..."
ARCH=$(get_architecture)
case "$ARCH" in
    amd64)
        INSTALLER_ARCH="x86_64-linux"
        ;;
    arm64)
        INSTALLER_ARCH="aarch64-linux"
        ;;
    *)
        echo "Error: Unsupported architecture for direct binary download: $ARCH"
        exit 1
        ;;
esac

# Create a temporary directory for the installer
INSTALL_DIR=$(mktemp -d)
INSTALLER_PATH="$INSTALL_DIR/nix-installer"

# Download the nix-installer directly
echo "Downloading nix-installer for $INSTALLER_ARCH..."
$CURL_CMD -k -L -o "$INSTALLER_PATH" "https://install.determinate.systems/nix/nix-installer-$INSTALLER_ARCH"
if [ $? -ne 0 ]; then
    echo "Error: Failed to download nix-installer."
    rm -rf "$INSTALL_DIR"
    exit 1
fi

# Make the installer executable
chmod +x "$INSTALLER_PATH"

# Run the installer
echo "Running nix-installer with options: $INSTALL_OPTS"
"$INSTALLER_PATH" $INSTALL_OPTS

# Check if installation was successful
if [ $? -eq 0 ]; then
    echo "Determinate Nix installation completed successfully!"
    
    # Source Nix environment if it exists
    if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        echo "Sourcing Nix environment..."
        . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    elif [ -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
        echo "Sourcing Nix daemon environment..."
        . "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    fi
    
    # Add Nix to PATH
    export PATH="/nix/var/nix/profiles/default/bin:$PATH"
    
    # Verify Nix is working
    if command -v nix > /dev/null 2>&1; then
        echo "Nix is working correctly. Version:"
        nix --version
    else
        echo "Nix installed but not found in PATH."
        echo "You can access nix with: /nix/var/nix/profiles/default/bin/nix"
        echo "Or add to your PATH with: export PATH=\"/nix/var/nix/profiles/default/bin:\$PATH\""
    fi
else
    echo "Determinate Nix installation failed."
    # Clean up
    rm -rf "$INSTALL_DIR"
    exit 1
fi

# Clean up
rm -rf "$INSTALL_DIR"

echo ""
echo "Installation process complete."
export PATH="/nix/var/nix/profiles/default/bin:$PATH"
exit 0

