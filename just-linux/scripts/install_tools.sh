#!/bin/sh

set -e

# Define the persistent directory for the flake
FLAKE_DIR="/opt/keyboard_kowboys/configs/nix"
FLAKE_FILE="$FLAKE_DIR/flake.nix"

echo "=== Installing packages with Nix using flakes ==="
echo "Started at $(date)"
echo ""

# Check if running as root
is_root() {
    [ "$(id -u)" -eq 0 ]
}

# Function to run commands with elevated privileges if needed
run_privileged() {
    if is_root; then
        # Already root, run command directly
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        # Use sudo if available
        sudo "$@"
    elif command -v doas >/dev/null 2>&1; then
        # Try doas as an alternative to sudo
        doas "$@"
    else
        echo "Warning: Neither running as root nor found sudo/doas"
        echo "Attempting to run command directly, may fail if privileges required"
        "$@"
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to ensure Nix is in the PATH
ensure_nix_in_path() {
    # Check if nix is directly in PATH
    if command_exists nix; then
        echo "Nix is in PATH"
        return 0
    fi
    
    echo "Nix not found in PATH, checking common installation locations..."
    
    # Check each possible location one by one (POSIX-compliant)
    # Standard multi-user installation
    if [ -x "/nix/var/nix/profiles/default/bin/nix" ]; then
        nix_path="/nix/var/nix/profiles/default/bin/nix"
        echo "Found Nix at: $nix_path"
        export PATH="/nix/var/nix/profiles/default/bin:$PATH"
        
        # Verify nix is now in PATH
        if command_exists nix; then
            echo "Successfully added Nix to PATH"
            return 0
        fi
    fi
    
    # Single-user installation
    if [ -x "$HOME/.nix-profile/bin/nix" ]; then
        nix_path="$HOME/.nix-profile/bin/nix"
        echo "Found Nix at: $nix_path"
        export PATH="$HOME/.nix-profile/bin:$PATH"
        
        # Verify nix is now in PATH
        if command_exists nix; then
            echo "Successfully added Nix to PATH"
            return 0
        fi
    fi
    
    # NixOS system location
    if [ -x "/run/current-system/sw/bin/nix" ]; then
        nix_path="/run/current-system/sw/bin/nix"
        echo "Found Nix at: $nix_path"
        export PATH="/run/current-system/sw/bin:$PATH"
        
        # Verify nix is now in PATH
        if command_exists nix; then
            echo "Successfully added Nix to PATH"
            return 0
        fi
    fi
    
    echo "Could not find Nix in any standard location"
    return 1
}

# Check for Nix (but don't install it)
check_nix() {
    # First ensure nix is in PATH
    if ! ensure_nix_in_path; then
        echo "Error: Nix could not be found. Please install Nix and try again."
        echo "Visit https://nixos.org/download.html for installation instructions."
        return 1
    fi
    
    echo "Nix is accessible"
    
    # Check for flakes capability
    if ! nix --version | grep -q "nix (Nix)"; then
        echo "Warning: Cannot determine Nix version. Flakes support may not be available."
    else
        echo "Nix version: $(nix --version)"
    fi
    
    # Enable flakes if not already enabled
    echo "Ensuring Nix flakes are enabled..."
    mkdir -p ~/.config/nix
    
    # Check if nix.conf exists and contains flakes configuration
    if [ -f ~/.config/nix/nix.conf ] && grep -q "experimental-features" ~/.config/nix/nix.conf; then
        echo "Nix flakes already enabled in config"
    else
        echo "Enabling Nix flakes in config..."
        echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
    fi
    
    # Set NIX_CONFIG environment variable for immediate effect without restart
    export NIX_CONFIG="experimental-features = nix-command flakes"
    
    return 0
}

# Create the flake file
create_flake() {
    echo "Creating Nix flake..."
    
    # Create directory for flake (with elevated privileges if needed)
    if [ ! -d "$FLAKE_DIR" ]; then
        echo "Creating directory $FLAKE_DIR (may require elevated privileges)..."
        run_privileged mkdir -p "$FLAKE_DIR" || { echo "Failed to create directory"; return 1; }
        
        # Set ownership - only if not already root
        if ! is_root; then
            user=$(whoami || id -un)
            run_privileged chown "$user" "$FLAKE_DIR" || { echo "Failed to set ownership"; return 1; }
        fi
    fi
    
    # Create the flake.nix file
    cat > "$FLAKE_FILE" << 'EOF'
{
  description = "Simple toolkit with packages including ChopChopGo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        
        # Use a pre-built binary from GitHub releases instead of building from source
        chopchopgoPackage = pkgs.stdenv.mkDerivation {
          pname = "ChopChopGo";
          version = "1.0.0";
          
          # Download the latest release from GitHub
          src = pkgs.fetchzip {
            url = "https://github.com/M00NLIG7/ChopChopGo/releases/download/v1.0.0-release-1/ChopChopGo-v1.0.0-release-1.zip";
            # Use this to find the correct hash
            # Either run with an incorrect hash or use `nix-prefetch-url --unpack URL`
            sha256 = "sha256-bO3uWI7VQSpETqGrRCYyZM5wUfL9RimyOuIXDES26Tk=";
            stripRoot = false;
          };
          
          # Additional runtime dependencies
          buildInputs = with pkgs; [ 
            systemd # May be needed at runtime
          ];
          
          # No build phase needed as we're using pre-built binaries
          dontBuild = true;
          
          # Just install the pre-built binary
          installPhase = ''
            mkdir -p $out/bin
            
            # The zip file contains a ChopChopGo directory with the binary inside
            cp $src/ChopChopGo/ChopChopGo $out/bin/
            chmod +x $out/bin/ChopChopGo
            
            # Copy sigma rules (using -r to copy directory contents)
            mkdir -p $out/share/ChopChopGo
            cp -r $src/ChopChopGo/rules $out/share/ChopChopGo/
            
            # Copy update script
            cp $src/ChopChopGo/update-rules.sh $out/share/ChopChopGo/
            chmod +x $out/share/ChopChopGo/update-rules.sh
          '';
        };
        
        # Just a simple list of package names
        packageNames = [
          "git"
          "nmap"
          "fd"
          "ripgrep"
          "lynis"
          "inotify-tools"
          "rsync"
          "tmux"
          "vim"
          "iptraf-ng"
          # Add more packages by name here
        ];
        
        # Function to generate package sets from the package names
        mkPackageSet = names: builtins.listToAttrs (
          map (name: {
            inherit name;
            value = pkgs.${name};
          }) names
        );
        
        # Generate the individual packages
        packageSet = mkPackageSet packageNames;
        
      in {
        # Dynamically expose individual packages
        packages = packageSet // {
          # Add ChopChopGo as a named package
          chopchopgo = chopchopgoPackage;

          # Include the default meta-package with all tools
          default = pkgs.buildEnv {
            name = "tools-env";
            paths = (map (name: pkgs.${name}) packageNames) ++ [ chopchopgoPackage ];
          };
        };

        # Also expose as legacy packages for compatibility
        legacyPackages = packageSet // { chopchopgo = chopchopgoPackage; };

        # Generate apps dynamically
        apps = builtins.listToAttrs (
          map (name: {
            inherit name;
            value = flake-utils.lib.mkApp { drv = pkgs.${name}; };
          }) packageNames
        ) // {
          chopchopgo = flake-utils.lib.mkApp { drv = chopchopgoPackage; };
        };

        # Simple shell with all packages
        devShell = pkgs.mkShell {
          buildInputs = (map (name: pkgs.${name}) packageNames) ++ [ chopchopgoPackage ];
        };
      }
    );
}
EOF
    
    echo "Flake file created at $FLAKE_FILE"
    return 0
}

# Install tools using the flake
install_tools_with_flake() {
    echo "Installing tools using the flake..."
    
    # Change to flake directory
    cd "$FLAKE_DIR"
    
    # Update the flake
    echo "Updating flake inputs..."
    nix flake update
    
    # Try to remove existing installation to avoid conflicts
    echo "Checking for existing installations..."
    if nix profile list | grep -q "nix-tools-flake"; then
        echo "Removing existing tools to avoid conflicts..."
        nix profile remove "nix-tools-flake" 2>/dev/null || true
    fi
    
    # Install all tools using the default package with a different priority
    echo "Installing tools from flake..."
    nix profile install .#default --priority 10
    
    # Simple verification - just check if the installation command succeeded
    if [ $? -eq 0 ]; then
        echo "Tools installed successfully"
        return 0
    else
        echo "Error: Failed to install tools"
        return 1
    fi
}

# Main process
echo "Starting installation process..."

# Check for Nix but don't install it
if check_nix; then
    echo "Proceeding with tool installation using flakes..."
    
    # Create the flake file
    if create_flake; then
        # Install tools using the flake
        if install_tools_with_flake; then
            echo ""
            echo "=== Installation Complete ==="
            echo "All tools have been installed to your system using Nix flakes"
            echo "Flake file is located at $FLAKE_FILE"
            echo ""
            echo "Installation completed at $(date)"
            exit 0
        else
            echo "Installation with flake failed"
        fi
    else
        echo "Failed to create flake"
    fi
    
    echo "=== Installation Aborted ==="
    echo ""
    echo "Installation aborted at $(date)"
    exit 1
else
    echo "Nix is not installed or could not be found in PATH. Please install Nix before running this script."
    echo "=== Installation Aborted ==="
    echo ""
    echo "Installation aborted at $(date)"
    exit 1
fi
