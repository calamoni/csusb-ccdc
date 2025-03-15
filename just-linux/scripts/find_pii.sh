#!/bin/sh
# Set path variable if provided
find_path=""
if [ -n "$1" ]; then
    find_path="$1"
fi
# Helper function to check if a command exists
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

# Check for ripgrep and fd-find (the faster Rust alternatives)
has_ripgrep=0
has_fd=0

if command_exists rg; then
    has_ripgrep=1
    echo "[+] Found ripgrep - using faster search capabilities"
fi

if command_exists fd; then
    has_fd=1
    echo "[+] Found fd-find - using faster file discovery"
fi

# Check for Nix package manager
check_nix

# Define search functions with both standard and fast tool implementations
grep_for_phone_numbers() {
    if [ "$has_ripgrep" -eq 1 ]; then
        rg -o '(\([0-9]{3}\) |[0-9]{3}-)[0-9]{3}-[0-9]{4}' "$1" 2>/dev/null
    else
        grep -E -o '(\([0-9]{3}\) |[0-9]{3}-)[0-9]{3}-[0-9]{4}' "$1" 2>/dev/null
    fi
}

grep_for_email_addresses() {
    if [ "$has_ripgrep" -eq 1 ]; then
        rg -o '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,6}' "$1" 2>/dev/null
    else
        grep -E -o '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,6}' "$1" 2>/dev/null
    fi
}

grep_for_social_security_numbers() {
    if [ "$has_ripgrep" -eq 1 ]; then
        rg -o '[0-9]{3}-[0-9]{2}-[0-9]{4}' "$1" 2>/dev/null
    else
        grep -E -o '[0-9]{3}-[0-9]{2}-[0-9]{4}' "$1" 2>/dev/null
    fi
}

grep_for_credit_card_numbers() {
    if [ "$has_ripgrep" -eq 1 ]; then
        # Fixed regex for credit card numbers to be compatible with both tools
        rg -o '^(?:4[0-9]{12}(?:[0-9]{3})?|[25][1-7][0-9]{14}|6(?:011|5[0-9][0-9])[0-9]{12}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|(?:2131|1800|35\d{3})\d{11})$' "$1" 2>/dev/null
    else
        grep -E -o '^(?:4[0-9]{12}(?:[0-9]{3})?|[25][1-7][0-9]{14}|6(?:011|5[0-9][0-9])[0-9]{12}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|(?:2131|1800|35\d{3})\d{11})$' "$1" 2>/dev/null
    fi
}

find_interesting_files_by_extension() {
    local doc_extensions="doc|docx|xls|xlsx|pdf|ppt|pptx|rtf|csv|odt|ods|odp|odg|odf|odc|odb|odm|docm|dotx|dotm|dot|wbk|xltx|xltm|xlt|xlam|xlsb|xla|xll|pptm|potx|potm|pot|ppsx|ppsm|pps|ppam"
    
    if [ "$has_fd" -eq 1 ]; then
        fd -t f -e doc -e docx -e xls -e xlsx -e pdf -e ppt -e pptx -e txt -e rtf -e csv -e odt -e ods -e odp -e odg -e odf -e odc -e odb -e odm -e docm -e dotx -e dotm -e dot -e wbk -e xltx -e xltm -e xlt -e xlam -e xlsb -e xla -e xll -e pptm -e potx -e potm -e pot -e ppsx -e ppsm -e pps -e ppam . "$1" 2>/dev/null
    else
        find "$1" -type f \( -name "*.doc" -o -name "*.docx" -o -name "*.xls" -o -name "*.xlsx" -o -name "*.pdf" -o -name "*.ppt" -o -name "*.pptx" -o -name "*.txt" -o -name "*.rtf" -o -name "*.csv" -o -name "*.odt" -o -name "*.ods" -o -name "*.odp" -o -name "*.odg" -o -name "*.odf" -o -name "*.odc" -o -name "*.odb" -o -name "*.odm" -o -name "*.docm" -o -name "*.dotx" -o -name "*.dotm" -o -name "*.dot" -o -name "*.wbk" -o -name "*.xltx" -o -name "*.xltm" -o -name "*.xlt" -o -name "*.xlam" -o -name "*.xlsb" -o -name "*.xla" -o -name "*.xll" -o -name "*.pptm" -o -name "*.potx" -o -name "*.potm" -o -name "*.pot" -o -name "*.ppsx" -o -name "*.ppsm" -o -name "*.pps" -o -name "*.ppam" \) 2>/dev/null
    fi
}

# Main search function
search() {
    if [ -z "$1" ] || [ ! -d "$1" ]; then
        echo "[-] Directory not found or is not accessible: $1"
        return 1
    fi

    echo "[+] Searching for phone numbers..."
    grep_for_phone_numbers "$1"
    
    echo "[+] Searching for email addresses..."
    grep_for_email_addresses "$1"
    
    echo "[+] Searching for social security numbers..."
    grep_for_social_security_numbers "$1"
    
    echo "[+] Searching for credit card numbers..."
    grep_for_credit_card_numbers "$1"
    
    echo "[+] Finding documents and other interesting files..."
    find_interesting_files_by_extension "$1"
}

# Search in specified path if provided
if [ -n "$find_path" ]; then
    echo "[+] Searching $find_path for PII."
    search "$find_path"
fi

# Search common locations
echo "[+] Searching /home for PII."
if [ -d "/home" ]; then
    search "/home"
else
    echo "[-] /home directory not found or is not accessible"
fi

echo "[+] Searching /var/www for PII."
if [ -d "/var/www" ]; then
    search "/var/www"
else
    echo "[-] /var/www directory not found or is not accessible"
fi

# Check for FTP configurations
# VSFTPD
if [ -f "/etc/vsftpd.conf" ]; then
    echo "[+] VSFTPD config file found. Checking for anon_root and local_root directories."
    
    anon_root=$(grep -E '^anon_root' /etc/vsftpd.conf | awk '{print $2}')
    if [ -n "$anon_root" ]; then
        echo "[+] anon_root found: $anon_root. Checking for PII."
        if [ -d "$anon_root" ]; then
            search "$anon_root"
        else
            echo "[-] $anon_root directory not found or is not accessible"
        fi
    fi
    
    local_root=$(grep -E '^local_root' /etc/vsftpd.conf | awk '{print $2}')
    if [ -n "$local_root" ]; then
        echo "[+] local_root found: $local_root. Checking for PII."
        if [ -d "$local_root" ]; then
            search "$local_root"
        else
            echo "[-] $local_root directory not found or is not accessible"
        fi
    fi
fi

# ProFTPD
if [ -f "/etc/proftpd/proftpd.conf" ]; then
    echo "[+] ProFTPD config file found. Checking for DefaultRoot directories."
    
    default_root=$(grep -E '^DefaultRoot' /etc/proftpd/proftpd.conf | awk '{print $2}')
    if [ -n "$default_root" ]; then
        # Remove quotes if present
        default_root=$(echo "$default_root" | sed 's/"//g')
        echo "[+] DefaultRoot found: $default_root. Checking for PII."
        if [ -d "$default_root" ]; then
            search "$default_root"
        else
            echo "[-] $default_root directory not found or is not accessible"
        fi
    fi
fi

# Samba
if [ -f "/etc/samba/smb.conf" ]; then
    echo "[+] Samba config file found. Checking for shares."
    
    # Extract path lines safely
    grep -E '^[[:space:]]*path[[:space:]]*=' /etc/samba/smb.conf | while read -r line; do
        # Extract share path and remove quotes
        share=$(echo "$line" | awk -F= '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/"//g')
        
        if [ -n "$share" ]; then
            echo "[+] Checking Samba share: $share for PII."
            if [ -d "$share" ]; then
                search "$share"
            else
                echo "[-] $share directory not found or is not accessible"
            fi
        fi
    done
fi

echo "[+] PII scan completed."
