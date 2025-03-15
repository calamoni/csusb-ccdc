#!/bin/sh

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

# Create the base directory first (before BusyBox installation)
echo "Creating base directory: $BASE_DIR"
mkdir -p "$BASE_DIR"

# Create necessary subdirectories 
echo "Creating required subdirectories..."
mkdir -p "$BASE_DIR/scripts" "$BASE_DIR/ops" "$BASE_DIR/backups" "$BASE_DIR/tools" "$BASE_DIR/configs" "$BASE_DIR/logs" "$BASE_DIR/playbooks" "$BASE_DIR/group_vars"

# Check if BusyBox is available, install it if needed
BUSYBOX_CMD=""
if ! command -v busybox > /dev/null 2>&1; then
    echo "BusyBox is not installed. Installing static BusyBox..."
    
    # Create tools directory if it doesn't exist
    TOOLS_DIR="$BASE_DIR/tools"
    mkdir -p "$TOOLS_DIR"
    
    # Path for the BusyBox binary
    BUSYBOX_PATH="$TOOLS_DIR/busybox"
    
    # Check if wget or curl is available for downloading
    if command -v wget > /dev/null 2>&1; then
        echo "Using wget to download BusyBox..."
        wget --no-check-certificate -q "https://github.com/ryanwoodsmall/static-binaries/raw/refs/heads/master/i686/busybox" -O "$BUSYBOX_PATH"
        DOWNLOAD_SUCCESS=$?
    elif command -v curl > /dev/null 2>&1; then
        echo "Using curl to download BusyBox..."
        curl -k -L -o "$BUSYBOX_PATH" "https://github.com/ryanwoodsmall/static-binaries/raw/refs/heads/master/i686/busybox" 
        DOWNLOAD_SUCCESS=$?
    else
        echo "Error: Neither wget nor curl is available. Cannot download BusyBox."
        DOWNLOAD_SUCCESS=1
    fi
    
    if [ $DOWNLOAD_SUCCESS -ne 0 ]; then
        echo "Error: Failed to download BusyBox."
        exit 1
    fi
    
    # Make the binary executable
    chmod +x "$BUSYBOX_PATH"
    echo "BusyBox installed to $BUSYBOX_PATH"
    
    # Try to create symlink in a PATH directory if possible
    if [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
        ln -sf "$BUSYBOX_PATH" "/usr/local/bin/busybox"
        echo "Created symlink at /usr/local/bin/busybox"
        BUSYBOX_CMD="/usr/local/bin/busybox"
    elif [ -d "/usr/bin" ] && [ -w "/usr/bin" ]; then
        ln -sf "$BUSYBOX_PATH" "/usr/bin/busybox"
        echo "Created symlink at /usr/bin/busybox"
        BUSYBOX_CMD="/usr/bin/busybox"
    elif [ -d "/bin" ] && [ -w "/bin" ]; then
        ln -sf "$BUSYBOX_PATH" "/bin/busybox"
        echo "Created symlink at /bin/busybox"
        BUSYBOX_CMD="/bin/busybox"
    else
        echo "Could not create symlink in PATH. Using full path to BusyBox."
        BUSYBOX_CMD="$BUSYBOX_PATH"
    fi
else
    BUSYBOX_CMD="busybox"
    echo "BusyBox is already installed."
fi

# Include BusyBox directory in PATH for this session
if [ -n "$BUSYBOX_CMD" ]; then
    echo "Adding BusyBox to PATH..."
    export PATH="$PATH:$(dirname "$BUSYBOX_CMD")"
fi

# Check if BusyBox unzip works and install it if not
if [ -n "$BUSYBOX_CMD" ]; then
    if ! $BUSYBOX_CMD unzip -h >/dev/null 2>&1; then
        echo "Configuring BusyBox unzip applet..."
        # Create a symlink for unzip in the same directory as busybox
        BUSYBOX_DIR=$(dirname "$BUSYBOX_CMD")
        ln -sf "$BUSYBOX_CMD" "$BUSYBOX_DIR/unzip"
        echo "Created unzip symlink at $BUSYBOX_DIR/unzip"
    fi
fi

# Check if curl is available, install it if needed
CURL_CMD=""
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
    
    # Install curl to tools directory
    CURL_PATH="$BASE_DIR/tools/curl"
    cp "$CURL_BINARY" "$CURL_PATH"
    chmod +x "$CURL_PATH"
    echo "curl installed to $CURL_PATH"
    
    # Clean up temp directory
    rm -rf "$TEMP_DIR"
    
    # Use the installed curl
    CURL_CMD="$CURL_PATH"
else
    CURL_CMD="curl"
    echo "curl is already installed."
fi

# Create temporary directory for downloading files
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

# Download the zip file
echo "Downloading Keyboard Kowboys files..."
if command -v wget > /dev/null 2>&1; then
    wget --no-check-certificate -q "https://github.com/CSUSB-CISO/csusb-ccdc/releases/download/CCDC-2024-2025/just-lin.zip" -O just-lin.zip
elif [ -n "$BUSYBOX_CMD" ]; then
    $BUSYBOX_CMD wget --no-check-certificate -q "https://github.com/CSUSB-CISO/csusb-ccdc/releases/download/CCDC-2024-2025/just-lin.zip" -O just-lin.zip
elif [ -n "$CURL_CMD" ]; then
    $CURL_CMD -k -L -o just-lin.zip "https://github.com/CSUSB-CISO/csusb-ccdc/releases/download/CCDC-2024-2025/just-lin.zip"
else
    echo "Error: No method available to download files."
    rm -rf "$TMP_DIR"
    exit 1
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
if [ -n "$BUSYBOX_CMD" ]; then
    echo "Using BusyBox unzip..."
    $BUSYBOX_CMD unzip -o just-lin.zip -d extract_temp
    UNZIP_SUCCESS=$?
else
    echo "BusyBox not available, trying system unzip..."
    if command -v unzip > /dev/null 2>&1; then
        unzip -o just-lin.zip -d extract_temp
        UNZIP_SUCCESS=$?
    else
        echo "Error: No unzip command available."
        UNZIP_SUCCESS=1
    fi
fi

if [ $UNZIP_SUCCESS -ne 0 ]; then
    echo "Error: Failed to extract zip file."
    rm -rf "$TMP_DIR"
    exit 1
fi

# List extracted contents
ls -la extract_temp

# Check what was extracted and copy all contents
if [ -d "extract_temp/just-linux" ]; then
    echo "Found 'just-linux' directory in the zip contents"
    
    # Check what's inside the just-linux directory
    if [ -f "extract_temp/just-linux/Justfile" ] || [ -f "extract_temp/just-linux/justfile" ]; then
        echo "Found Justfile inside just-linux directory, copying all files and directories..."
        
        # Copy Justfile
        if [ -f "extract_temp/just-linux/Justfile" ]; then
            cp "extract_temp/just-linux/Justfile" "$BASE_DIR/"
        elif [ -f "extract_temp/just-linux/justfile" ]; then
            cp "extract_temp/just-linux/justfile" "$BASE_DIR/Justfile"
        fi
        
        # Copy scripts directory if it exists
        if [ -d "extract_temp/just-linux/scripts" ]; then
            echo "Copying scripts directory..."
            cp -r "extract_temp/just-linux/scripts/"* "$BASE_DIR/scripts/" 2>/dev/null || true
        fi
        
        # Copy playbooks directory if it exists
        if [ -d "extract_temp/just-linux/playbooks" ]; then
            echo "Copying playbooks directory..."
            cp -r "extract_temp/just-linux/playbooks/"* "$BASE_DIR/playbooks/" 2>/dev/null || true
        fi
        
        # Copy group_vars directory if it exists
        if [ -d "extract_temp/just-linux/group_vars" ]; then
            echo "Copying group_vars directory..."
            cp -r "extract_temp/just-linux/group_vars/"* "$BASE_DIR/group_vars/" 2>/dev/null || true
        fi
        
        # Copy hosts.ini if it exists
        if [ -f "extract_temp/just-linux/hosts.ini" ]; then
            echo "Copying hosts.ini..."
            cp "extract_temp/just-linux/hosts.ini" "$BASE_DIR/" 2>/dev/null || true
        fi
        
        # Copy any other files at the root level
        echo "Copying any other files at root level..."
        for file in extract_temp/just-linux/*; do
            if [ -f "$file" ] && [ "$(basename "$file")" != "Justfile" ] && [ "$(basename "$file")" != "justfile" ] && [ "$(basename "$file")" != "hosts.ini" ]; then
                cp "$file" "$BASE_DIR/" 2>/dev/null || true
            fi
        done
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
        elif [ -n "$BUSYBOX_CMD" ]; then
            $BUSYBOX_CMD wget --no-check-certificate -q "$JUST_URL" -O "$JUST_DIR/just.tar.gz"
        elif [ -n "$CURL_CMD" ]; then
            $CURL_CMD -k -L -o "$JUST_DIR/just.tar.gz" "$JUST_URL"
        else
            echo "Error: No method available to download files."
            rm -rf "$JUST_DIR"
            exit 1
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
playbooks_dir := base_dir + "/playbooks"
group_vars_dir := base_dir + "/group_vars"

# Display available commands with descriptions
default:
    @just --list

# Initialize directory structure (run once or after reset)
init:
    #!/bin/sh
    echo "setting up keyboard kowboys operation environment..."
    mkdir -p {{base_dir}} {{scripts_dir}} {{ops_dir}} {{backup_dir}} {{tools_dir}} {{config_dir}} {{log_dir}} {{playbooks_dir}} {{group_vars_dir}}
    chmod -R 750 {{base_dir}}
    echo "directory structure created at {{base_dir}}"
EOF
fi

# Clean up
rm -rf "$TMP_DIR"

# Display BusyBox information at the end
echo "BusyBox information:"
if [ -n "$BUSYBOX_CMD" ]; then
    echo "  Path: $BUSYBOX_CMD"
    echo "  Installed at: $(which $BUSYBOX_CMD 2>/dev/null || echo "$BUSYBOX_CMD")"
    echo "  Version: $($BUSYBOX_CMD | head -n 1 2>/dev/null || echo "Unknown")"
else
    echo "  Not installed or not found"
fi
echo ""

echo "==========================================================="
echo "Keyboard Kowboys environment has been set up successfully!"
echo "Base directory: $BASE_DIR"
echo ""
if [ -x "$BIN_DIR/just" ]; then
    echo "just command installed at: $BIN_DIR/just"
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

# Verify created directories
echo "Verifying directory structure:"
for dir in "$BASE_DIR/scripts" "$BASE_DIR/ops" "$BASE_DIR/backups" "$BASE_DIR/tools" "$BASE_DIR/configs" "$BASE_DIR/logs" "$BASE_DIR/playbooks" "$BASE_DIR/group_vars"; do
    if [ -d "$dir" ]; then
        echo "✓ $dir exists"
    else
        echo "✗ $dir does not exist"
    fi
done

exit 0
