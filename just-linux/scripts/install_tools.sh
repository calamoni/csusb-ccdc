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

# Function to ensure Nix is in the PATH - this is a critical function
ensure_nix_in_path() {
    # Check if nix is directly in PATH
    if command_exists nix; then
        echo "Nix is in PATH"
        return 0
    fi
    
    echo "Nix not found in PATH, checking common installation locations..."
    
    # First, try to source the appropriate profile script
    for profile_script in \
        "$HOME/.nix-profile/etc/profile.d/nix.sh" \
        "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" \
        "/etc/profile.d/nix.sh" \
        "/etc/profile.d/nix-daemon.sh"; do
        
        if [ -f "$profile_script" ]; then
            echo "Sourcing Nix profile from: $profile_script"
            # Source the profile script
            . "$profile_script"
            
            # Check if nix is now in PATH
            if command_exists nix; then
                echo "Successfully added Nix to PATH via profile script"
                return 0
            fi
        fi
    done
    
    # If sourcing didn't work, try adding common Nix paths directly
    for nix_path in \
        "/nix/var/nix/profiles/default/bin" \
        "$HOME/.nix-profile/bin" \
        "/run/current-system/sw/bin"; do
        
        if [ -d "$nix_path" ] && [ -x "$nix_path/nix" ]; then
            echo "Found Nix at: $nix_path/nix"
            export PATH="$nix_path:$PATH"
            
            # Verify nix is now in PATH
            if command_exists nix; then
                echo "Successfully added Nix to PATH"
                # Make PATH change visible to other processes (if running as root)
                if is_root; then
                    echo "export PATH=\"$nix_path:\$PATH\"" >> /etc/profile.d/nix-path.sh
                    chmod +x /etc/profile.d/nix-path.sh
                    echo "Added Nix path to /etc/profile.d/nix-path.sh"
                fi
                return 0
            fi
        fi
    done
    
    echo "Could not find Nix in any standard location"
    return 1
}

# Check for Nix (but don't install it)
check_nix() {
    # First ensure nix is in PATH - this is CRITICAL
    if ! ensure_nix_in_path; then
        echo "Error: Nix could not be found. Please install Nix and try again."
        echo "Visit https://nixos.org/download.html for installation instructions."
        return 1
    fi
    
    echo "Nix is accessible at: $(which nix)"
    
    # Print version information for debugging
    nix_version=$(nix --version)
    echo "Nix version: $nix_version"
    
    # Ensure Nix store exists and is writable
    if [ ! -d "/nix/store" ]; then
        echo "Error: /nix/store does not exist. Nix installation may be incomplete."
        return 1
    fi
    
    # Ensure config directory exists
    mkdir -p "$HOME/.config/nix"
    
    # Enable flakes and nix-command in configuration
    if [ -f "$HOME/.config/nix/nix.conf" ]; then
        if ! grep -q "experimental-features" "$HOME/.config/nix/nix.conf"; then
            echo "Adding flakes to Nix config..."
            echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"
        fi
    else
        echo "Creating Nix config with flakes enabled..."
        echo "experimental-features = nix-command flakes" > "$HOME/.config/nix/nix.conf"
    fi
    
    # Set environment variable for immediate effect
    export NIX_CONFIG="experimental-features = nix-command flakes"
    
    # Test if flakes work
    echo "Testing Nix flakes functionality..."
    if ! nix flake --help >/dev/null 2>&1; then
        echo "Error: Nix flakes not available. Your Nix version may be too old or not properly configured."
        return 1
    fi
    
    echo "Nix flakes are working correctly"
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
            url = "https://github.com/M00NLIG7/ChopChopGo/releases/download/v1.0.0-release-1/v1.0.0-release-1.zip";
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

# Install tools using the flake - with extra error handling
install_tools_with_flake() {
    echo "Installing tools using the flake..."
    
    # Change to flake directory
    cd "$FLAKE_DIR"
    
    # Make sure we can still find nix
    if ! command_exists nix; then
        echo "Error: Lost access to nix command. Re-ensuring nix is in PATH..."
        ensure_nix_in_path || return 1
    fi
    
    # First just try a simple flake check to verify flake works
    echo "Checking flake validity..."
    if ! nix flake check; then
        echo "Error: Flake check failed. The flake may be invalid."
        return 1
    fi
    
    # Update the flake inputs
    echo "Updating flake inputs..."
    nix flake update
    
    # Try to remove existing installation to avoid conflicts
    echo "Checking for existing installations..."
    if nix profile list 2>/dev/null | grep -q "nix-tools-flake"; then
        echo "Removing existing tools to avoid conflicts..."
        nix profile remove "nix-tools-flake" 2>/dev/null || true
    fi
    
    # First, try installing with --no-build-hook to bypass any post-build hook issues
    echo "Installing tools from flake (with no build hook)..."
    if nix profile install .#default --no-use-registries --option build-use-substitutes true --option build-use-sandbox false --no-write-lock-file --option post-build-hook "" --priority 10; then
        echo "Tools installed successfully with --no-build-hook option"
        return 0
    fi
    
    # If that didn't work, try a more conservative approach
    echo "First attempt failed, trying conservative approach..."
    if nix profile install .#default --option build-users-group "" --option sandbox false --priority 10; then
        echo "Tools installed successfully with conservative options"
        return 0
    fi
    
    # If still failing, try one last approach installing packages individually
    echo "Second attempt failed, trying to install packages individually..."
    success=false
    
    # Start with basic packages that are less likely to have issues
    for pkg in git vim ripgrep fd; do
        echo "Installing individual package: $pkg"
        if nix profile install ".#$pkg" --option sandbox false --no-write-lock-file; then
            echo "Successfully installed $pkg"
            success=true
        else
            echo "Failed to install $pkg, continuing with others"
        fi
    done
    
    if $success; then
        echo "Some tools were installed successfully"
        return 0
    else
        echo "All installation attempts failed"
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
            echo "Tools have been installed to your system using Nix flakes"
            echo "Flake file is located at $FLAKE_FILE"
            echo ""
            echo "To ensure tools are in your PATH, run:"
            echo "export PATH=\"$HOME/.nix-profile/bin:\$PATH\""
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
