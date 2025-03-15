#!/bin/sh
# Improved BusyBox-Compatible Keyboard Kowboys Setup Script
# Sets up the directory structure and extracts zip content

set -e  # Exit on any error

# Default base directory (can be overridden with command line argument)
BASE_DIR="/opt/keyboard_kowboys"
BIN_DIR="/bin"  # Default bin directory for BusyBox

# Parse command line arguments
if [ $# -gt 0 ]; then
    BASE_DIR="$1"
fi

echo "Setting up Keyboard Kowboys environment at: $BASE_DIR"

# Function to determine system architecture
get_architecture() {
    arch=$(uname -m)
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

# Check if BusyBox is available, install it if needed
if ! command -v busybox > /dev/null 2>&1; then
    echo "BusyBox is not installed. Installing static BusyBox..."
    
    # Check if wget or curl is available for downloading
    if command -v wget > /dev/null 2>&1; then
        DL_CMD="wget --no-check-certificate -q"
    elif command -v curl > /dev/null 2>&1; then
        DL_CMD="curl -k -L -o busybox"
    else
        echo "Error: Neither wget nor curl is available. Cannot download BusyBox."
        exit 1
    fi
    
    # Create a temporary directory
    TEMP_DIR=$(mktemp -d)
    BUSYBOX_BINARY="$TEMP_DIR/busybox"
    
    echo "Downloading static BusyBox..."
    if command -v wget > /dev/null 2>&1; then
        wget --no-check-certificate -q "https://github.com/ryanwoodsmall/static-binaries/raw/refs/heads/master/i686/busybox" -O "$BUSYBOX_BINARY"
    else
        curl -k -L -o "$BUSYBOX_BINARY" "https://github.com/ryanwoodsmall/static-binaries/raw/refs/heads/master/i686/busybox"
    fi
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download BusyBox."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Make the binary executable
    chmod +x "$BUSYBOX_BINARY"
    
    # Install BusyBox to local directory
    cp "$BUSYBOX_BINARY" ./busybox
    chmod +x ./busybox
    echo "BusyBox installed to $(pwd)/busybox"
    
    # Set BUSYBOX_CMD to use our local copy
    BUSYBOX_CMD="./busybox"
    
    # Clean up temp directory
    rm -rf "$TEMP_DIR"
else
    BUSYBOX_CMD="busybox"
    echo "BusyBox is already installed."
fi

# Check if curl is available, install it if needed
if ! command -v curl > /dev/null 2>&1; then
    echo "curl is not installed. Installing..."
    
    # Check if wget is available or use our BusyBox wget
    if command -v wget > /dev/null 2>&1; then
        DL_CMD="wget --no-check-certificate -q"
    elif [ -n "$BUSYBOX_CMD" ]; then
        DL_CMD="$BUSYBOX_CMD wget --no-check-certificate -q"
    else
        echo "Error: Neither curl, wget, nor BusyBox wget is available."
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
    if command -v wget > /dev/null 2>&1; then
        wget --no-check-certificate -q "https://github.com/moparisthebest/static-curl/releases/latest/download/curl-$ARCH" -O "$CURL_BINARY"
    elif [ -n "$BUSYBOX_CMD" ]; then
        $BUSYBOX_CMD wget --no-check-certificate -q "https://github.com/moparisthebest/static-curl/releases/latest/download/curl-$ARCH" -O "$CURL_BINARY"
    fi
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download curl."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Make the binary executable
    chmod +x "$CURL_BINARY"
    
    # In busybox environments, keep curl in current directory
    cp "$CURL_BINARY" ./curl
    chmod +x ./curl
    echo "curl installed to $(pwd)/curl"
    
    # Clean up temp directory
    rm -rf "$TEMP_DIR"
    
    # Use the local curl
    CURL_CMD="./curl"
else
    CURL_CMD="curl"
    echo "curl is already installed."
fi

# Create the base directory
echo "Creating base directory: $BASE_DIR"
mkdir -p "$BASE_DIR"

# Create necessary subdirectories 
echo "Creating required subdirectories..."
mkdir -p "$BASE_DIR/scripts" "$BASE_DIR/ops" "$BASE_DIR/backups" "$BASE_DIR/tools" "$BASE_DIR/configs" "$BASE_DIR/logs"

# Create temporary directory for downloading files
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

# Download the zip file
echo "Downloading Keyboard Kowboys files..."
if command -v wget > /dev/null 2>&1; then
    wget --no-check-certificate -q "https://github.com/CSUSB-CISO/csusb-ccdc/releases/download/CCDC-2024-2025/just-lin.zip" -O just-lin.zip
else
    $CURL_CMD -k -L -o just-lin.zip "https://github.com/CSUSB-CISO/csusb-ccdc/releases/download/CCDC-2024-2025/just-lin.zip"
fi

# Check if download was successful
if [ ! -f just-lin.zip ]; then
    echo "Failed to download the zip file. Please check your internet connection."
    rm -rf "$TMP_DIR"
    exit 1
fi

# Extract files to a temporary directory using BusyBox unzip
echo "Examining zip contents using BusyBox unzip..."
mkdir -p extract_temp

# Use our installed BusyBox or system BusyBox for unzip
echo "Using BusyBox unzip..."
$BUSYBOX_CMD unzip -o just-lin.zip -d extract_temp

# If BusyBox unzip fails, try system unzip as fallback
if [ $? -ne 0 ]; then
    echo "BusyBox unzip failed, trying system unzip if available..."
    if command -v unzip > /dev/null 2>&1; then
        unzip -o just-lin.zip -d extract_temp
    else
        echo "Error: Failed to extract zip file. No working unzip command available."
        rm -rf "$TMP_DIR"
        exit 1
    fi
fi

# List extracted contents
ls -la extract_temp

# Check what was extracted
if [ -d "extract_temp/just-linux" ]; then
    echo "Found 'just-linux' directory in the zip contents"
    
    # Check what's inside the just-linux directory
    if [ -f "extract_temp/just-linux/Justfile" ] || [ -f "extract_temp/just-linux/justfile" ]; then
        echo "Found Justfile inside just-linux directory, copying files..."
        
        # Copy Justfile
        if [ -f "extract_temp/just-linux/Justfile" ]; then
            cp "extract_temp/just-linux/Justfile" "$BASE_DIR/"
        elif [ -f "extract_temp/just-linux/justfile" ]; then
            cp "extract_temp/just-linux/justfile" "$BASE_DIR/Justfile"
        fi
        
        # Copy scripts if they exist
        if [ -d "extract_temp/just-linux/scripts" ]; then
            cp -r "extract_temp/just-linux/scripts/"* "$BASE_DIR/scripts/" 2>/dev/null || true
        fi
    else
        # This means the just-linux directory doesn't have the expected structure
        echo "Could not find Justfile inside just-linux directory"
        # Try copying everything from just-linux to the base directory
        cp -r "extract_temp/just-linux/"* "$BASE_DIR/" 2>/dev/null || true
    fi
else
    echo "No 'just-linux' directory found, copying all extracted files to $BASE_DIR"
    cp -r extract_temp/* "$BASE_DIR/" 2>/dev/null || true
fi

# Set proper permissions
echo "Setting permissions..."
chmod -R 750 "$BASE_DIR"
chmod 755 "$BASE_DIR"/scripts/*.sh 2>/dev/null || true

# Install 'just' if not already installed
if ! command -v just &> /dev/null; then
    echo "Installing 'just' command..."
    
    # Get system architecture for just
    JUST_ARCH=""
    case "$(uname -m)" in
        x86_64)
            JUST_ARCH="x86_64-unknown-linux-musl"
            ;;
        aarch64|arm64)
            JUST_ARCH="aarch64-unknown-linux-musl"
            ;;
        i686|i386)
            JUST_ARCH="i686-unknown-linux-musl"
            ;;
        *)
            echo "Error: Unsupported architecture for just: $(uname -m)"
            echo "Please install just manually: https://github.com/casey/just"
            ;;
    esac
    
    if [ -n "$JUST_ARCH" ]; then
        JUST_VERSION="1.40.0"
        JUST_URL="https://github.com/casey/just/releases/download/$JUST_VERSION/just-$JUST_VERSION-$JUST_ARCH.tar.gz"
        JUST_DIR=$(mktemp -d)
        
        echo "Downloading just $JUST_VERSION for $JUST_ARCH..."
        if command -v wget > /dev/null 2>&1; then
            wget --no-check-certificate -q "$JUST_URL" -O "$JUST_DIR/just.tar.gz"
        else
            $CURL_CMD -k -L -o "$JUST_DIR/just.tar.gz" "$JUST_URL"
        fi
        
        if [ $? -ne 0 ]; then
            echo "Error: Failed to download just."
            rm -rf "$JUST_DIR"
        else
            echo "Extracting just..."
            tar -xzf "$JUST_DIR/just.tar.gz" -C "$JUST_DIR"
            
            # Try to find a writable directory in PATH
            echo "Finding writable directory in PATH..."
            for dir in /usr/local/bin /usr/bin /bin; do
                if [ -d "$dir" ] && [ -w "$dir" ]; then
                    BIN_DIR="$dir"
                    echo "Found writable directory: $BIN_DIR"
                    break
                fi
            done
            
            # If no writable standard directory found, try to create one
            if [ ! -d "$BIN_DIR" ] || [ ! -w "$BIN_DIR" ]; then
                echo "No writable directory found in standard paths"
                
                # Try to create /usr/local/bin if it doesn't exist
                if [ ! -d "/usr/local/bin" ]; then
                    echo "Creating /usr/local/bin directory..."
                    mkdir -p /usr/local/bin 2>/dev/null
                    if [ $? -eq 0 ]; then
                        BIN_DIR="/usr/local/bin"
                        echo "Created $BIN_DIR directory"
                    fi
                fi
                
                # If still no success, use /tmp as last resort
                if [ ! -d "$BIN_DIR" ] || [ ! -w "$BIN_DIR" ]; then
                    echo "Using /tmp as fallback location"
                    BIN_DIR="/tmp"
                fi
            fi
            
            echo "Installing just to $BIN_DIR..."
            cp "$JUST_DIR/just" "$BIN_DIR/"
            chmod +x "$BIN_DIR/just"
            
            # Verify installation
            if [ -f "$BIN_DIR/just" ]; then
                echo "just installed successfully to $BIN_DIR/just"
                
                # Create symlink to /bin if not already in standard path
                if [ "$BIN_DIR" = "/tmp" ]; then
                    echo "Creating symlink in /bin for accessibility..."
                    if [ -d "/bin" ] && [ -w "/bin" ]; then
                        ln -sf "$BIN_DIR/just" "/bin/just" 2>/dev/null
                        if [ $? -eq 0 ]; then
                            echo "Created symlink at /bin/just"
                            BIN_DIR="/bin"  # Update BIN_DIR to refer to the symlink
                        fi
                    fi
                fi
            else
                echo "Error: just installation failed."
            fi
        fi
        
        # Clean up
        rm -rf "$JUST_DIR"
    fi
fi

# If Justfile was not found in the zip, create a simple one
if [ ! -f "$BASE_DIR/Justfile" ] && [ ! -f "$BASE_DIR/justfile" ]; then
    echo "No Justfile found, creating a simple one..."
    cat > "$BASE_DIR/Justfile" << 'EOF'
base_dir := "/opt/keyboard_kowboys"
scripts_dir := base_dir + "/scripts"
ops_dir := base_dir + "/ops"
backup_dir := base_dir + "/backups"
tools_dir := base_dir + "/tools"
config_dir := base_dir + "/configs"
log_dir := base_dir + "/logs"

# Display available commands with descriptions
default:
    @just --list

# Initialize directory structure (run once or after reset)
init:
    #!/bin/sh
    echo "setting up keyboard kowboys operation environment..."
    mkdir -p {{base_dir}} {{scripts_dir}} {{ops_dir}} {{backup_dir}} {{tools_dir}} {{config_dir}} {{log_dir}}
    chmod -R 750 {{base_dir}}
    echo "directory structure created at {{base_dir}}"
EOF
fi

# Clean up
rm -rf "$TMP_DIR"

echo "==========================================================="
echo "Keyboard Kowboys environment has been set up successfully!"
echo "Base directory: $BASE_DIR"
echo ""
if [ -x "$BIN_DIR/just" ]; then
    echo "just command installed 
    echo ""
    if [ "$BIN_DIR" = "/tmp" ]; then
        echo "Since just is installed in /tmp, you can run it using:"
        echo "  /tmp/just --list"
        echo ""
        echo "Or add it to your PATH temporarily:"
        echo "  export PATH=\"/tmp:\$PATH\""
        echo "  just --list"
    else
        echo "To use just, simply run:"
        echo "  just --list"
    fi
    echo ""
fi
echo "==========================================================="

exit 0
