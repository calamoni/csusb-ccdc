#!/bin/sh

# Default configuration
BASE_DIR="${KK_BASE_DIR:-/opt/keyboard_kowboys}"
BACKUP_ROOT="${KK_BACKUP_DIR:-$BASE_DIR/backups}"
LOG_DIR="${KK_LOG_DIR:-$BASE_DIR/logs}"
LOG_FILE="$LOG_DIR/diff.log"
CONFIG_DIR="${KK_CONFIG_DIR:-$BASE_DIR/configs}"
TEMP_DIR="/tmp/system_diff_$$"
VERBOSE=false
COLOR=true
OUTPUT_MODE="console"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "WARNING: Some diff operations require root privileges"
        return 1
    fi
    return 0
}

# Function to log messages
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")" || true
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    
    if [ "$VERBOSE" = true ] || [ "$level" = "ERROR" ]; then 
        echo "[$level] $message"
    fi
}

# Function to output diff results
output_diff() {
    local title="$1"
    local content="$2"
    
    # Format the title
    local header="=== $title ==="
    local separator="================="
    
    echo "$separator"
    echo "$header"
    echo "$separator"
    echo "$content"
    echo ""
}

# Function to create a current snapshot of system state
create_current_snapshot() {
    local target="$1"
    local snapshot_dir="$TEMP_DIR/current"
    
    mkdir -p "$snapshot_dir"
    
    case "$target" in
        "ports"|"all")
            if command_exists ss; then
                ss -tuln > "$snapshot_dir/listening_ports.txt"
            elif command_exists netstat; then
                netstat -tuln > "$snapshot_dir/listening_ports.txt"
            else
                log "ERROR" "Neither ss nor netstat found for port comparison"
                echo "No tool available to capture port information" > "$snapshot_dir/listening_ports.txt"
            fi
            ;;
        "connections"|"all")
            if command_exists ss; then
                ss -tunapl > "$snapshot_dir/network_connections.txt"
            elif command_exists netstat; then
                netstat -tunapl > "$snapshot_dir/network_connections.txt"
            else
                log "ERROR" "Neither ss nor netstat found for connection comparison"
                echo "No tool available to capture connection information" > "$snapshot_dir/network_connections.txt"
            fi
            ;;
        "processes"|"all")
            ps aux | sort -k 2 > "$snapshot_dir/processes.txt"
            ;;
        "services"|"all")
            if command_exists systemctl; then
                systemctl list-units --type=service --state=active > "$snapshot_dir/active_services.txt"
                systemctl list-unit-files --type=service > "$snapshot_dir/service_status.txt"
            elif command_exists service; then
                service --status-all > "$snapshot_dir/service_status.txt"
            else
                log "ERROR" "No service management tool found for service comparison"
                echo "No service management tool available" > "$snapshot_dir/service_status.txt"
            fi
            ;;
        "users"|"all")
            who > "$snapshot_dir/logged_users.txt"
            last -n 20 > "$snapshot_dir/recent_logins.txt"
            ;;
        "mounts"|"all")
            mount > "$snapshot_dir/mounts.txt"
            df -h > "$snapshot_dir/disk_usage.txt"
            ;;
        "packages"|"all")
            if command_exists dpkg; then
                dpkg --get-selections > "$snapshot_dir/packages.list"
            elif command_exists rpm; then
                rpm -qa | sort > "$snapshot_dir/packages.list"
            elif command_exists nix-env; then
                nix-env -q > "$snapshot_dir/packages.list"
            else
                log "ERROR" "No package manager found for package comparison"
                echo "No package manager tool available" > "$snapshot_dir/packages.list"
            fi
            ;;
    esac
}

# Function to find the right backup file with fallback logic
find_backup_file() {
    local system_type="$1"
    local filename="$2"
    
    # Helper function to check a path and its resolved symlinks
    check_path() {
        local path="$1"
        if [ -f "$path" ]; then
            log "INFO" "Found backup file at: $path"
            echo "$path"
            return 0
        fi
        
        # If it's a symlink, also check the resolved path
        if [ -L "$path" ]; then
            local resolved_path=$(readlink -f "$path" 2>/dev/null)
            if [ -f "$resolved_path" ]; then
                log "INFO" "Found backup file at resolved path: $resolved_path"
                echo "$resolved_path"
                return 0
            fi
        fi
        
        return 1
    }
    
    # Try different patterns for all possible paths
    
    # 1. First check the specific system type with the exact filename in system_info
    if [ "$system_type" != "all" ]; then
        # Check in both latest and possible dated directories
        for subdir in "latest" "$(date +%Y%m%d)" ""; do
            # Skip empty subdir
            if [ -z "$subdir" ]; then continue; fi
            
            # Try full path
            local path="$BACKUP_ROOT/$system_type/$subdir/system_info/$filename"
            if check_path "$path"; then
                return 0
            fi
            
            # If latest is a symlink, check the target
            if [ -L "$BACKUP_ROOT/$system_type/$subdir" ]; then
                local link_target=$(readlink -f "$BACKUP_ROOT/$system_type/$subdir" 2>/dev/null)
                if [ -d "$link_target" ]; then
                    path="$link_target/system_info/$filename"
                    if check_path "$path"; then
                        return 0
                    fi
                fi
            fi
        done
    fi
    
    # 2. Then check the "all" backup
    for subdir in "latest" "$(date +%Y%m%d)" ""; do
        # Skip empty subdir
        if [ -z "$subdir" ]; then continue; fi
        
        # Try full path in all backup
        local path="$BACKUP_ROOT/all/$subdir/system_info/$filename"
        if check_path "$path"; then
            return 0
        fi
        
        # If latest is a symlink, check the target
        if [ -L "$BACKUP_ROOT/all/$subdir" ]; then
            local link_target=$(readlink -f "$BACKUP_ROOT/all/$subdir" 2>/dev/null)
            if [ -d "$link_target" ]; then
                path="$link_target/system_info/$filename"
                if check_path "$path"; then
                    return 0
                fi
            fi
        fi
    done
    
    # 3. As a last resort, search for the file in the backup directory
    log "INFO" "Backup file not found in standard locations, searching entire backup directory..."
    found=$(find "$BACKUP_ROOT" -name "$filename" -type f 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        log "INFO" "Found backup file at: $found"
        echo "$found"
        return 0
    fi
    
    # Not found anywhere
    log "ERROR" "Backup file $filename not found in any location"
    echo ""
    return 1
}

# Function to perform diff on services
diff_services() {
    local system_type="$1"
    
    # Create current snapshot
    local current_file="$TEMP_DIR/current/active_services.txt"
    if [ ! -f "$current_file" ]; then
        mkdir -p "$TEMP_DIR/current"
        if command_exists systemctl; then
            systemctl list-units --type=service --state=active > "$current_file"
        else
            log "ERROR" "systemctl not found, cannot create services snapshot"
            output_diff "ACTIVE SERVICES" "ERROR: systemctl not found"
            return 1
        fi
    fi
    
    # Find the backup file using the fallback logic
    local backup_file=$(find_backup_file "$system_type" "active_services.txt")
    
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log "ERROR" "Backup service file not found"
        if [ "$system_type" = "all" ]; then
            output_diff "ACTIVE SERVICES" "ERROR: Service backup file not found. Run 'just backup all' first."
        else
            output_diff "ACTIVE SERVICES" "ERROR: Service backup file not found. Run 'just backup $system_type' or 'just backup all' first."
        fi
        return 1
    fi
    
    log "INFO" "Using backup file: $backup_file"
    log "INFO" "Using current file: $current_file"
    
    # Compare service names
    grep "\.service" "$backup_file" | awk '{print $1}' | sort > "$TEMP_DIR/backup_services.txt" 2>/dev/null || true
    grep "\.service" "$current_file" | awk '{print $1}' | sort > "$TEMP_DIR/current_services.txt" 2>/dev/null || true
    
    # Check if extraction worked
    if [ ! -s "$TEMP_DIR/backup_services.txt" ] || [ ! -s "$TEMP_DIR/current_services.txt" ]; then
        # Fallback to direct file comparison
        log "WARNING" "Service extraction failed, falling back to direct comparison"
        diff_result=$(diff -u "$backup_file" "$current_file" 2>/dev/null)
        diff_status=$?
    else
        # Process each file to create formatted output with service names and status
        grep "\.service" "$backup_file" | awk '{print $1, $3, $4}' | sort > "$TEMP_DIR/backup_services_detailed.txt" 2>/dev/null || true
        grep "\.service" "$current_file" | awk '{print $1, $3, $4}' | sort > "$TEMP_DIR/current_services_detailed.txt" 2>/dev/null || true
        
        diff_result=$(diff -u "$TEMP_DIR/backup_services_detailed.txt" "$TEMP_DIR/current_services_detailed.txt" 2>/dev/null)
        diff_status=$?
    fi
    
    # Output results
    if [ $diff_status -eq 0 ]; then
        output_diff "ACTIVE SERVICES" "No changes in active services"
    else
        output_diff "ACTIVE SERVICES" "$diff_result"
        
        # Also identify new and removed services
        if [ -s "$TEMP_DIR/backup_services.txt" ] && [ -s "$TEMP_DIR/current_services.txt" ]; then
            # Find new services
            comm -13 "$TEMP_DIR/backup_services.txt" "$TEMP_DIR/current_services.txt" > "$TEMP_DIR/new_services.txt" 2>/dev/null || true
            if [ -s "$TEMP_DIR/new_services.txt" ]; then
                output_diff "NEW SERVICES" "$(cat "$TEMP_DIR/new_services.txt")"
            fi
            
            # Find removed services
            comm -23 "$TEMP_DIR/backup_services.txt" "$TEMP_DIR/current_services.txt" > "$TEMP_DIR/removed_services.txt" 2>/dev/null || true
            if [ -s "$TEMP_DIR/removed_services.txt" ]; then
                output_diff "REMOVED SERVICES" "$(cat "$TEMP_DIR/removed_services.txt")"
            fi
        fi
    fi
}

# Function to compare processes
diff_processes() {
    local system_type="$1"
    local current_file="$TEMP_DIR/current/processes.txt"
    
    # Find the backup file using the fallback logic
    local backup_file=$(find_backup_file "$system_type" "processes.txt")
    
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log "ERROR" "Backup process file not found"
        output_diff "RUNNING PROCESSES" "ERROR: Process backup file not found. Run 'just backup $system_type' or 'just backup all' first."
        return 1
    fi
    
    if [ ! -f "$current_file" ]; then
        log "ERROR" "Current process snapshot not found: $current_file"
        output_diff "RUNNING PROCESSES" "ERROR: Failed to generate current process snapshot."
        return 1
    fi
    
    # Extract just the command names for a cleaner comparison
    awk '{print $11}' "$backup_file" | sort | uniq -c | sort -nr > "$TEMP_DIR/backup_proc.processed" 2>/dev/null || true
    awk '{print $11}' "$current_file" | sort | uniq -c | sort -nr > "$TEMP_DIR/current_proc.processed" 2>/dev/null || true
    
    # Perform diff
    diff -u "$TEMP_DIR/backup_proc.processed" "$TEMP_DIR/current_proc.processed" > "$TEMP_DIR/diff_output.txt" 2>/dev/null || true
    
    # Output results
    if [ ! -s "$TEMP_DIR/diff_output.txt" ]; then
        output_diff "RUNNING PROCESSES" "No changes in running processes"
    else
        output_diff "RUNNING PROCESSES" "$(cat "$TEMP_DIR/diff_output.txt")"
    fi
    
    # Also look for new processes not in backup
    comm -13 "$TEMP_DIR/backup_proc.processed" "$TEMP_DIR/current_proc.processed" > "$TEMP_DIR/new_processes.txt" 2>/dev/null || true
    if [ -s "$TEMP_DIR/new_processes.txt" ]; then
        output_diff "NEW PROCESSES" "$(cat "$TEMP_DIR/new_processes.txt")"
    fi
}

# Function to compare ports
diff_ports() {
    local system_type="$1"
    local current_file="$TEMP_DIR/current/listening_ports.txt"
    
    # Find the backup file using the fallback logic
    local backup_file=$(find_backup_file "$system_type" "listening_ports.txt")
    
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log "ERROR" "Backup port file not found"
        output_diff "LISTENING PORTS" "ERROR: Port backup file not found. Run 'just backup $system_type' or 'just backup all' first."
        return 1
    fi
    
    if [ ! -f "$current_file" ]; then
        log "ERROR" "Current port snapshot not found: $current_file"
        output_diff "LISTENING PORTS" "ERROR: Failed to generate current port snapshot."
        return 1
    fi
    
    # Process both files to standardize output but preserve port numbers
    # Extract just the protocol, state, and address:port
    grep "LISTEN\|UNCONN" "$backup_file" | awk '{print $1, $2, $5}' | sort > "$TEMP_DIR/backup_ports.processed"
    grep "LISTEN\|UNCONN" "$current_file" | awk '{print $1, $2, $5}' | sort > "$TEMP_DIR/current_ports.processed"
    
    # Perform diff
    if command_exists colordiff && [ "$COLOR" = true ]; then
        diff_result=$(colordiff -u "$TEMP_DIR/backup_ports.processed" "$TEMP_DIR/current_ports.processed")
    else
        diff_result=$(diff -u "$TEMP_DIR/backup_ports.processed" "$TEMP_DIR/current_ports.processed")
    fi
    
    # Output results
    if [ -z "$diff_result" ]; then
        output_diff "LISTENING PORTS" "No changes detected"
    else
        output_diff "LISTENING PORTS" "$diff_result"
        
        # Also show a summary of what ports were added or removed
        grep "^+" "$TEMP_DIR/diff.txt" | grep -v "^+++" | sed 's/^+//' > "$TEMP_DIR/added_ports.txt"
        grep "^-" "$TEMP_DIR/diff.txt" | grep -v "^---" | sed 's/^-//' > "$TEMP_DIR/removed_ports.txt"
        
        if [ -s "$TEMP_DIR/added_ports.txt" ]; then
            output_diff "NEW LISTENING PORTS" "$(cat "$TEMP_DIR/added_ports.txt")"
        fi
        
        if [ -s "$TEMP_DIR/removed_ports.txt" ]; then
            output_diff "REMOVED LISTENING PORTS" "$(cat "$TEMP_DIR/removed_ports.txt")"
        fi
    fi
    
    # Also provide a more human-readable format that focuses on the actual services
    echo "# Extracting service details for better readability" > "$TEMP_DIR/backup_services.txt"
    echo "# Extracting service details for better readability" > "$TEMP_DIR/current_services.txt"
    
    if command_exists ss; then
        # For ss output
        grep "LISTEN" "$backup_file" | awk '{split($5, a, ":"); printf "%-10s %-20s %-10s\n", $1, a[1], a[2]}' | sort -k3 -n >> "$TEMP_DIR/backup_services.txt"
        grep "LISTEN" "$current_file" | awk '{split($5, a, ":"); printf "%-10s %-20s %-10s\n", $1, a[1], a[2]}' | sort -k3 -n >> "$TEMP_DIR/current_services.txt"
    elif command_exists netstat; then
        # For netstat output
        grep "LISTEN" "$backup_file" | awk '{split($4, a, ":"); printf "%-10s %-20s %-10s\n", $1, a[1], a[2]}' | sort -k3 -n >> "$TEMP_DIR/backup_services.txt"
        grep "LISTEN" "$current_file" | awk '{split($4, a, ":"); printf "%-10s %-20s %-10s\n", $1, a[1], a[2]}' | sort -k3 -n >> "$TEMP_DIR/current_services.txt"
    fi
    
    # Perform diff on the service details
    service_diff=$(diff -u "$TEMP_DIR/backup_services.txt" "$TEMP_DIR/current_services.txt")
    if [ $? -ne 0 ]; then
        output_diff "SERVICE PORT DETAILS (PROTOCOL, ADDRESS, PORT)" "$service_diff"
    fi
    
    # Simple service lookup for common ports
    if [ -s "$TEMP_DIR/added_ports.txt" ] || [ -s "$TEMP_DIR/removed_ports.txt" ]; then
        output_diff "PORT-SERVICE MAPPING" "Common ports and their services:
22: SSH
53: DNS
80: HTTP
443: HTTPS
25: SMTP
110: POP3
143: IMAP
3306: MySQL
5432: PostgreSQL
8080: HTTP Alternate
21: FTP
23: Telnet
161: SNMP
389: LDAP
636: LDAPS
"
    fi
}

# Function to compare connections
diff_processes() {
    local system_type="$1"
    local current_file="$TEMP_DIR/current/processes.txt"
    
    # Find the backup file using the fallback logic
    local backup_file=$(find_backup_file "$system_type" "processes.txt")
    
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log "ERROR" "Backup process file not found"
        output_diff "RUNNING PROCESSES" "ERROR: Process backup file not found. Run 'just backup $system_type' or 'just backup all' first."
        return 1
    fi
    
    if [ ! -f "$current_file" ]; then
        log "ERROR" "Current process snapshot not found: $current_file"
        output_diff "RUNNING PROCESSES" "ERROR: Failed to generate current process snapshot."
        return 1
    fi
    
    # Extract important process information including command, user, and arguments
    awk '{printf "%-15s %-20s %s\n", $1, $11, $12 $13 $14 $15}' "$backup_file" | sort > "$TEMP_DIR/backup_proc.detailed" 2>/dev/null || true
    awk '{printf "%-15s %-20s %s\n", $1, $11, $12 $13 $14 $15}' "$current_file" | sort > "$TEMP_DIR/current_proc.detailed" 2>/dev/null || true
    
    # Also extract just command names and count for a simpler view
    awk '{print $11}' "$backup_file" | sort | uniq -c | sort -nr > "$TEMP_DIR/backup_proc.processed" 2>/dev/null || true
    awk '{print $11}' "$current_file" | sort | uniq -c | sort -nr > "$TEMP_DIR/current_proc.processed" 2>/dev/null || true
    
    # Perform diff on the detailed output
    detailed_diff=$(diff -u "$TEMP_DIR/backup_proc.detailed" "$TEMP_DIR/current_proc.detailed")
    detailed_status=$?
    
    # Perform diff on the simple counts
    simple_diff=$(diff -u "$TEMP_DIR/backup_proc.processed" "$TEMP_DIR/current_proc.processed")
    simple_status=$?
    
    # Output results
    if [ $simple_status -eq 0 ]; then
        output_diff "PROCESS COUNT SUMMARY" "No changes in process counts"
    else
        # Get just the significant changes (not just PID changes)
        echo "$simple_diff" | grep "^[+-][^+-]" | grep -v "^\+\+\+\|---" > "$TEMP_DIR/proc_changes.txt"
        
        if [ -s "$TEMP_DIR/proc_changes.txt" ]; then
            output_diff "PROCESS COUNT CHANGES" "$(cat "$TEMP_DIR/proc_changes.txt")"
        else
            output_diff "PROCESS COUNT SUMMARY" "No significant process count changes"
        fi
    fi
    
    # Also identify specific processes of interest that were added or removed
    comm -13 <(awk '{print $11}' "$backup_file" | sort | uniq) <(awk '{print $11}' "$current_file" | sort | uniq) > "$TEMP_DIR/new_processes.txt" 2>/dev/null || true
    if [ -s "$TEMP_DIR/new_processes.txt" ]; then
        output_diff "NEW PROCESSES" "$(cat "$TEMP_DIR/new_processes.txt")"
        
        # Show details for new processes
        echo "Details for new processes:" > "$TEMP_DIR/new_proc_details.txt"
        for proc in $(cat "$TEMP_DIR/new_processes.txt"); do
            grep "$proc" "$TEMP_DIR/current_proc.detailed" >> "$TEMP_DIR/new_proc_details.txt"
        done
        
        if [ -s "$TEMP_DIR/new_proc_details.txt" ]; then
            output_diff "NEW PROCESS DETAILS" "$(cat "$TEMP_DIR/new_proc_details.txt")"
        fi
    fi
    
    # Find removed processes
    comm -23 <(awk '{print $11}' "$backup_file" | sort | uniq) <(awk '{print $11}' "$current_file" | sort | uniq) > "$TEMP_DIR/removed_processes.txt" 2>/dev/null || true
    if [ -s "$TEMP_DIR/removed_processes.txt" ]; then
        output_diff "REMOVED PROCESSES" "$(cat "$TEMP_DIR/removed_processes.txt")"
        
        # Show details for removed processes
        echo "Details for removed processes:" > "$TEMP_DIR/removed_proc_details.txt"
        for proc in $(cat "$TEMP_DIR/removed_processes.txt"); do
            grep "$proc" "$TEMP_DIR/backup_proc.detailed" >> "$TEMP_DIR/removed_proc_details.txt"
        done
        
        if [ -s "$TEMP_DIR/removed_proc_details.txt" ]; then
            output_diff "REMOVED PROCESS DETAILS" "$(cat "$TEMP_DIR/removed_proc_details.txt")"
        fi
    fi
}
# Function to compare users
diff_users() {
    local system_type="$1"
    local current_file="$TEMP_DIR/current/logged_users.txt"
    
    # Find the backup file using the fallback logic
    local backup_file=$(find_backup_file "$system_type" "logged_users.txt")
    
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log "ERROR" "Backup user file not found"
        output_diff "LOGGED IN USERS" "WARNING: User backup file not found. Run 'just backup $system_type' or 'just backup all' first."
        return 1
    fi
    
    if [ ! -f "$current_file" ]; then
        log "ERROR" "Current user snapshot not found: $current_file"
        output_diff "LOGGED IN USERS" "WARNING: Failed to generate current user snapshot."
        return 1
    fi
    
    # Extract usernames only
    awk '{print $1}' "$backup_file" | sort -u > "$TEMP_DIR/backup_users.processed" 2>/dev/null || true
    awk '{print $1}' "$current_file" | sort -u > "$TEMP_DIR/current_users.processed" 2>/dev/null || true
    
    # Perform diff
    if command_exists colordiff && [ "$COLOR" = true ]; then
        diff_result=$(colordiff -u "$TEMP_DIR/backup_users.processed" "$TEMP_DIR/current_users.processed" 2>/dev/null)
    else
        diff_result=$(diff -u "$TEMP_DIR/backup_users.processed" "$TEMP_DIR/current_users.processed" 2>/dev/null)
    fi
    
    # Output results
    if [ -z "$diff_result" ]; then
        output_diff "LOGGED IN USERS" "No changes in logged users"
    else
        output_diff "LOGGED IN USERS" "$diff_result"
    fi
}

# Function to compare mounts
diff_mounts() {
    local system_type="$1"
    local current_file="$TEMP_DIR/current/mounts.txt"
    
    # Find the backup file using the fallback logic
    local backup_file=$(find_backup_file "$system_type" "mounts.txt")
    
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log "ERROR" "Backup mount file not found"
        output_diff "MOUNTED FILESYSTEMS" "WARNING: Mount backup file not found. Run 'just backup $system_type' or 'just backup all' first."
        return 1
    fi
    
    if [ ! -f "$current_file" ]; then
        log "ERROR" "Current mount snapshot not found: $current_file"
        output_diff "MOUNTED FILESYSTEMS" "WARNING: Failed to generate current mount snapshot."
        return 1
    fi
    
    # Extract mount points only for cleaner comparison
    awk '{print $3}' "$backup_file" | sort > "$TEMP_DIR/backup_mounts.processed" 2>/dev/null || true
    awk '{print $3}' "$current_file" | sort > "$TEMP_DIR/current_mounts.processed" 2>/dev/null || true
    
    # Perform diff
    if command_exists colordiff && [ "$COLOR" = true ]; then
        diff_result=$(colordiff -u "$TEMP_DIR/backup_mounts.processed" "$TEMP_DIR/current_mounts.processed" 2>/dev/null)
    else
        diff_result=$(diff -u "$TEMP_DIR/backup_mounts.processed" "$TEMP_DIR/current_mounts.processed" 2>/dev/null)
    fi
    
    # Output results
    if [ -z "$diff_result" ]; then
        output_diff "MOUNTED FILESYSTEMS" "No changes in mounted filesystems"
    else
        output_diff "MOUNTED FILESYSTEMS" "$diff_result"
    fi
}

# Function to compare packages
diff_packages() {
    local system_type="$1"
    local current_file="$TEMP_DIR/current/packages.list"
    
    # Find the backup file using the fallback logic
    local backup_file=$(find_backup_file "$system_type" "packages.list")
    
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log "ERROR" "Backup package file not found"
        output_diff "INSTALLED PACKAGES" "WARNING: Package backup file not found. Run 'just backup $system_type' or 'just backup all' first."
        return 1
    fi
    
    if [ ! -f "$current_file" ]; then
        log "ERROR" "Current package snapshot not found: $current_file"
        output_diff "INSTALLED PACKAGES" "WARNING: Failed to generate current package snapshot."
        return 1
    fi
    
    # Create a temp file for the diff output
    diff -u "$backup_file" "$current_file" > "$TEMP_DIR/diff_output.txt" 2>/dev/null || true
    
    # Check if there are any differences
    if [ ! -s "$TEMP_DIR/diff_output.txt" ]; then
        output_diff "INSTALLED PACKAGES" "No changes in installed packages"
    else
        # For packages, it's often useful to just see what's added/removed
        added=$(grep -E "^\+" "$TEMP_DIR/diff_output.txt" | grep -v "^+++" | sed 's/^+//' 2>/dev/null || echo "")
        removed=$(grep -E "^-" "$TEMP_DIR/diff_output.txt" | grep -v "^---" | sed 's/^-//' 2>/dev/null || echo "")
        
        if [ -n "$added" ]; then
            output_diff "NEWLY INSTALLED PACKAGES" "$added"
        fi
        
        if [ -n "$removed" ]; then
            output_diff "REMOVED PACKAGES" "$removed"
        fi
    fi
}

# Function to compare configuration files
diff_configs() {
    local system_type="$1"
    
    # Common configuration files to check
    local config_files="/etc/passwd /etc/group /etc/hosts /etc/resolv.conf /etc/hostname /etc/fstab /etc/ssh/sshd_config"
    
    for config in $config_files; do
        local base_name=$(basename "$config")
        
        # Search for the config file in backup directories by base name
        local backup_config=""
        
        # Find the corresponding file in backup using the search function
        if [ -f "$config" ]; then
            # Use the find_backup_file function to locate the file
            for search_file in "$base_name" "etc/$base_name" "etc/ssh/$base_name"; do
                backup_config=$(find_backup_file "$system_type" "$search_file")
                if [ -n "$backup_config" ]; then
                    break
                fi
            done
            
            if [ -n "$backup_config" ]; then
                # Perform diff
                if command_exists colordiff && [ "$COLOR" = true ]; then
                    diff_result=$(colordiff -u "$backup_config" "$config" 2>/dev/null)
                else
                    diff_result=$(diff -u "$backup_config" "$config" 2>/dev/null)
                fi
                
                # Output results
                if [ -z "$diff_result" ]; then
                    output_diff "CONFIG: $config" "No changes"
                else
                    output_diff "CONFIG: $config" "$diff_result"
                fi
            else
                log "WARNING" "Could not find backup version of $config"
            fi
        else
            log "WARNING" "Config file $config does not exist on current system"
        fi
    done
}

# Function to compare specific files
diff_files() {
    local system_type="$1"
    local files="$2"
    
    for file in $files; do
        if [ -f "$file" ]; then
            local base_name=$(basename "$file")
            
            # Find the corresponding file in backup
            backup_file=$(find_backup_file "$system_type" "$base_name")
            
            if [ -n "$backup_file" ]; then
                # Perform diff
                if command_exists colordiff && [ "$COLOR" = true ]; then
                    diff_result=$(colordiff -u "$backup_file" "$file" 2>/dev/null)
                else
                    diff_result=$(diff -u "$backup_file" "$file" 2>/dev/null)
                fi
                
                # Output results
                if [ -z "$diff_result" ]; then
                    output_diff "FILE: $file" "No changes"
                else
                    output_diff "FILE: $file" "$diff_result"
                fi
            else
                log "WARNING" "Could not find backup version of $file"
                output_diff "FILE: $file" "WARNING: Could not find file in backup"
            fi
        else
            log "WARNING" "File $file does not exist on current system"
            output_diff "FILE: $file" "WARNING: File does not exist on current system"
        fi
    done
}

# Parse command line arguments (POSIX-compliant way)
POSITIONAL=""
SPECIFIC_FILES=""
SYSTEM_TYPE="all"
BACKUP_DATE=""

while [ $# -gt 0 ]; do
    key="$1"
    
    case $key in
        -h|--help)
            echo "Usage: $0 [OPTIONS] <target>"
            echo "Run 'just help diff' for more information"
            exit 0
            ;;
        -s|--system-type)
            SYSTEM_TYPE="$2"
            shift
            shift
            ;;
        -d|--date)
            BACKUP_DATE="$2"
            shift
            shift
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -n|--no-color)
            COLOR=false
            shift
            ;;
        -f|--files)
            SPECIFIC_FILES="$2"
            shift
            shift
            ;;
        *)
            if [ -z "$POSITIONAL" ]; then
                POSITIONAL="$1"
            else
                POSITIONAL="$POSITIONAL $1"
            fi
            shift
            ;;
    esac
done

# Restore positional parameters
set -- $POSITIONAL

# Check for required arguments
if [ $# -lt 1 ]; then
    echo "ERROR: Missing target argument"
    echo "Usage: $0 [OPTIONS] <target>"
    exit 1
fi

TARGET="$1"

# Fix backups directory path if needed
if [ ! -d "$BACKUP_ROOT" ]; then
    mkdir -p "$BACKUP_ROOT"
fi

# Initialize log file directory
if [ "$LOG_FILE" != "/dev/stdout" ]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/diff-$$.log"
fi

# Log script start
log "INFO" "Starting System State Diff Tool"
log "INFO" "Target: $TARGET, Backup directory: $BACKUP_ROOT, System type: $SYSTEM_TYPE"

# Create temp directory for processing
mkdir -p "$TEMP_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Create current snapshot based on target
log "INFO" "Creating current snapshot for: $TARGET"
create_current_snapshot "$TARGET"

# Check root permissions
check_root || log "WARNING" "Some diff operations may not have complete access"

# Perform diff based on target
case "$TARGET" in
    "ports")
        diff_ports "$SYSTEM_TYPE"
        ;;
    "connections")
        diff_connections "$SYSTEM_TYPE"
        ;;
    "processes")
        diff_processes "$SYSTEM_TYPE"
        ;;
    "services")
        diff_services "$SYSTEM_TYPE"
        ;;
    "users")
        diff_users "$SYSTEM_TYPE"
        ;;
    "mounts")
        diff_mounts "$SYSTEM_TYPE"
        ;;
    "packages")
        diff_packages "$SYSTEM_TYPE"
        ;;
    "configs")
        diff_configs "$SYSTEM_TYPE"
        ;;
    "files")
        if [ -z "$SPECIFIC_FILES" ]; then
            log "ERROR" "No files specified for comparison"
            echo "ERROR: You must specify files to compare using the -f option"
            exit 1
        fi
        diff_files "$SYSTEM_TYPE" "$SPECIFIC_FILES"
        ;;
    "all")
        diff_ports "$SYSTEM_TYPE"
        diff_connections "$SYSTEM_TYPE"
        diff_processes "$SYSTEM_TYPE"
        diff_services "$SYSTEM_TYPE"
        diff_users "$SYSTEM_TYPE"
        diff_mounts "$SYSTEM_TYPE"
        diff_packages "$SYSTEM_TYPE"
        diff_configs "$SYSTEM_TYPE"
        ;;
    *)
        log "ERROR" "Unknown target: $TARGET"
        echo "ERROR: Unknown target: $TARGET"
        echo "Run 'just help diff' for more information"
        exit 1
        ;;
esac

log "INFO" "Diff completed successfully"
exit 0
