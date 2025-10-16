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

# Function to check if running on BusyBox
is_busybox() {
    if command_exists busybox; then
        # Check if the system is primarily BusyBox
        if busybox 2>/dev/null | head -1 | grep -q "BusyBox"; then
            return 0
        fi
    fi
    return 1
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
            # BusyBox-compatible last command (no -n flag support)
            if is_busybox; then
                # BusyBox last doesn't support -n, use head instead
                last 2>/dev/null | head -20 > "$snapshot_dir/recent_logins.txt" || true
            else
                # Full last command supports -n
                last -n 20 > "$snapshot_dir/recent_logins.txt" 2>/dev/null || true
            fi
            ;;
        "mounts"|"all")
            mount > "$snapshot_dir/mounts.txt"
            df -h > "$snapshot_dir/disk_usage.txt"
            ;;
        "packages"|"all")

            has_pkg_manager=false
            
            if command_exists apk; then
                has_pkg_manager=true
                apk info | sort >> "$snapshot_dir/packages.list"
            fi
            if command_exists apt; then
                has_pkg_manager=true
                apt list --installed 2>/dev/null | sort >> "$snapshot_dir/packages.list"
            fi
            if command_exists dpkg; then
                has_pkg_manager=true
                dpkg --get-selections >> "$snapshot_dir/packages.list"
            fi
            if command_exists rpm; then
                has_pkg_manager=true
                rpm -qa | sort >> "$snapshot_dir/packages.list"
            fi
            if command_exists nix-env; then
                has_pkg_manager=true
                nix-env -q >> "$snapshot_dir/packages.list"
            fi
            if [ "$has_pkg_manager" = false ]; then
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
    
    log "INFO" "Looking for backup file: $filename"
    log "INFO" "System type: $system_type"
    log "INFO" "Backup root: $BACKUP_ROOT"
    
    # Show the actual backup directory structure
    if [ -d "$BACKUP_ROOT" ]; then
        log "INFO" "Backup directory structure:"
        if command_exists fd; then
            fd --max-depth 3 --type d --base-directory "$BACKUP_ROOT" 2>/dev/null | sed "s|^|$BACKUP_ROOT/|" | while read dir; do
                log "INFO" "  $dir"
            done
        else
            find "$BACKUP_ROOT" -maxdepth 3 -type d 2>/dev/null | while read dir; do
                log "INFO" "  $dir"
            done
        fi
    else
        log "ERROR" "Backup root directory does not exist: $BACKUP_ROOT"
    fi
    
    # Helper function to check a path and its resolved symlinks
    check_path() {
        local path="$1"
        log "INFO" "Checking path: $path"
        
        if [ -f "$path" ]; then
            log "INFO" "Found backup file at: $path"
            echo "$path"
            return 0
        fi
        
        # If it's a symlink, also check the resolved path
        if [ -L "$path" ]; then
            local resolved_path=$(readlink -f "$path" 2>/dev/null)
            log "INFO" "Path is symlink, resolved to: $resolved_path"
            if [ -f "$resolved_path" ]; then
                log "INFO" "Found backup file at resolved path: $resolved_path"
                echo "$resolved_path"
                return 0
            fi
        fi
        
        # Check if the directory exists but file doesn't
        local dir_path=$(dirname "$path")
        if [ -d "$dir_path" ]; then
            log "INFO" "Directory exists: $dir_path"
            log "INFO" "Contents of $dir_path:"
            ls -la "$dir_path" 2>/dev/null | while read line; do
                log "INFO" "  $line"
            done
        else
            log "INFO" "Directory does not exist: $dir_path"
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
    
    # 3. Check for files directly in backup directories (without system_info subdirectory)
    # This handles cases where the backup structure might be different
    for subdir in "latest" "$(date +%Y%m%d)" ""; do
        # Skip empty subdir
        if [ -z "$subdir" ]; then continue; fi
        
        # Try direct path in all backup
        local path="$BACKUP_ROOT/all/$subdir/$filename"
        if check_path "$path"; then
            return 0
        fi
        
        # If latest is a symlink, check the target
        if [ -L "$BACKUP_ROOT/all/$subdir" ]; then
            local link_target=$(readlink -f "$BACKUP_ROOT/all/$subdir" 2>/dev/null)
            if [ -d "$link_target" ]; then
                path="$link_target/$filename"
                if check_path "$path"; then
                    return 0
                fi
            fi
        fi
    done
    
    # 4. As a last resort, search for the file in the backup directory
    log "INFO" "Backup file not found in standard locations, searching entire backup directory..."
    if command_exists fd; then
        found=$(fd --type f --glob "$filename" --base-directory "$BACKUP_ROOT" 2>/dev/null | sed "s|^|$BACKUP_ROOT/|" | head -1)
    else
        found=$(find "$BACKUP_ROOT" -name "$filename" -type f 2>/dev/null | head -1)
    fi
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
        log "ERROR" "Backup service file not found for system type: $system_type"
        log "ERROR" "Searched in: $BACKUP_ROOT/$system_type/latest/ and $BACKUP_ROOT/all/latest/"
        if [ "$system_type" = "all" ]; then
            output_diff "ACTIVE SERVICES" "ERROR: Service backup file not found.
  Searched locations:
    - $BACKUP_ROOT/all/latest/system_info/active_services.txt
    - $BACKUP_ROOT/all/$(date +%Y%m%d)/system_info/active_services.txt

  Fix: Run 'just backup all' to create a baseline backup first."
        else
            output_diff "ACTIVE SERVICES" "ERROR: Service backup file not found.
  Searched locations:
    - $BACKUP_ROOT/$system_type/latest/system_info/active_services.txt
    - $BACKUP_ROOT/all/latest/system_info/active_services.txt

  Fix: Run 'just backup $system_type' or 'just backup all' first."
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
        log "ERROR" "Backup process file not found for system type: $system_type"
        log "ERROR" "Searched in: $BACKUP_ROOT/$system_type/latest/ and $BACKUP_ROOT/all/latest/"
        output_diff "RUNNING PROCESSES" "ERROR: Process backup file not found.
  Searched in: $BACKUP_ROOT/$system_type/latest/system_info/ and $BACKUP_ROOT/all/latest/system_info/
  Fix: Run 'just backup $system_type' or 'just backup all' first."
        return 1
    fi
    
    if [ ! -f "$current_file" ]; then
        log "ERROR" "Current process snapshot not found: $current_file"
        output_diff "RUNNING PROCESSES" "ERROR: Failed to generate current process snapshot."
        return 1
    fi
    
    # Extract just the command names (field 11) for comparison
    # Skip header line and sort/count unique process names
    tail -n +2 "$backup_file" 2>/dev/null | awk '{print $11}' | sort | uniq -c | sort -nr > "$TEMP_DIR/backup_proc.processed" || true
    tail -n +2 "$current_file" 2>/dev/null | awk '{print $11}' | sort | uniq -c | sort -nr > "$TEMP_DIR/current_proc.processed" || true

    # Perform diff - this shows changes in process counts
    diff -u "$TEMP_DIR/backup_proc.processed" "$TEMP_DIR/current_proc.processed" > "$TEMP_DIR/diff_output.txt" 2>/dev/null || true

    # Output results with better formatting
    if [ ! -s "$TEMP_DIR/diff_output.txt" ]; then
        output_diff "RUNNING PROCESSES (by count)" "No changes in running processes"
    else
        # Filter to show only meaningful changes (lines with process names)
        grep -E "^\+[[:space:]]*[0-9]|^-[[:space:]]*[0-9]" "$TEMP_DIR/diff_output.txt" > "$TEMP_DIR/proc_count_changes.txt" 2>/dev/null || true
        if [ -s "$TEMP_DIR/proc_count_changes.txt" ]; then
            output_diff "RUNNING PROCESSES (count changes)" "$(cat "$TEMP_DIR/proc_count_changes.txt")"
        else
            output_diff "RUNNING PROCESSES (by count)" "No significant changes in process counts"
        fi
    fi
    
    # Also identify specific processes of interest that were added or removed
    # Use temp files instead of process substitution for POSIX compliance
    # Skip header and extract unique process names
    tail -n +2 "$backup_file" 2>/dev/null | awk '{print $11}' | sort -u > "$TEMP_DIR/backup_proc_names.txt" || true
    tail -n +2 "$current_file" 2>/dev/null | awk '{print $11}' | sort -u > "$TEMP_DIR/current_proc_names.txt" || true

    # Find new processes (in current but not in backup)
    comm -13 "$TEMP_DIR/backup_proc_names.txt" "$TEMP_DIR/current_proc_names.txt" > "$TEMP_DIR/new_processes.txt" 2>/dev/null || true
    if [ -s "$TEMP_DIR/new_processes.txt" ]; then
        output_diff "NEW PROCESSES (not in backup)" "$(cat "$TEMP_DIR/new_processes.txt")"
    fi

    # Find removed processes (in backup but not in current)
    comm -23 "$TEMP_DIR/backup_proc_names.txt" "$TEMP_DIR/current_proc_names.txt" > "$TEMP_DIR/removed_processes.txt" 2>/dev/null || true
    if [ -s "$TEMP_DIR/removed_processes.txt" ]; then
        output_diff "REMOVED PROCESSES (were in backup)" "$(cat "$TEMP_DIR/removed_processes.txt")"
    fi
}

# Function to compare ports
diff_ports() {
    local system_type="$1"
    local current_file="$TEMP_DIR/current/listening_ports.txt"
    
    # Find the backup file using the fallback logic
    local backup_file=$(find_backup_file "$system_type" "listening_ports.txt")
    
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log "ERROR" "Backup port file not found for system type: $system_type"
        log "ERROR" "Searched in: $BACKUP_ROOT/$system_type/latest/ and $BACKUP_ROOT/all/latest/"
        output_diff "LISTENING PORTS" "ERROR: Port backup file not found.
  Searched in: $BACKUP_ROOT/$system_type/latest/system_info/ and $BACKUP_ROOT/all/latest/system_info/
  Fix: Run 'just backup $system_type' or 'just backup all' first."
        return 1
    fi
    
    if [ ! -f "$current_file" ]; then
        log "ERROR" "Current port snapshot not found: $current_file"
        output_diff "LISTENING PORTS" "ERROR: Failed to generate current port snapshot."
        return 1
    fi
    
    # Process both files to standardize output but preserve port numbers
    # Need to detect format: ss uses field 5, netstat uses field 4 for Local Address
    # Check if this is ss output (has "Netid" header) or netstat output (has "Proto" header)

    # For backup file - detect format and extract accordingly
    if head -1 "$backup_file" 2>/dev/null | grep -q "Netid"; then
        # ss format: field 5 is Local Address:Port
        grep -E "LISTEN|UNCONN" "$backup_file" 2>/dev/null | awk '{print $1, $5}' | sort -u > "$TEMP_DIR/backup_ports.processed" || true
    else
        # netstat format: field 4 is Local Address:Port
        grep -E "LISTEN|UNCONN" "$backup_file" 2>/dev/null | awk '{print $1, $4}' | sort -u > "$TEMP_DIR/backup_ports.processed" || true
    fi

    # For current file - detect format and extract accordingly
    if head -1 "$current_file" 2>/dev/null | grep -q "Netid"; then
        # ss format
        grep -E "LISTEN|UNCONN" "$current_file" 2>/dev/null | awk '{print $1, $5}' | sort -u > "$TEMP_DIR/current_ports.processed" || true
    else
        # netstat format
        grep -E "LISTEN|UNCONN" "$current_file" 2>/dev/null | awk '{print $1, $4}' | sort -u > "$TEMP_DIR/current_ports.processed" || true
    fi
    
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

        # Write diff result to file for further processing
        echo "$diff_result" > "$TEMP_DIR/ports_diff.txt"

        # Also show a summary of what ports were added or removed
        grep "^+" "$TEMP_DIR/ports_diff.txt" | grep -v "^+++" | sed 's/^+//' > "$TEMP_DIR/added_ports.txt" 2>/dev/null || true
        grep "^-" "$TEMP_DIR/ports_diff.txt" | grep -v "^---" | sed 's/^-//' > "$TEMP_DIR/removed_ports.txt" 2>/dev/null || true

        if [ -s "$TEMP_DIR/added_ports.txt" ]; then
            output_diff "NEW LISTENING PORTS" "$(cat "$TEMP_DIR/added_ports.txt")"
        fi

        if [ -s "$TEMP_DIR/removed_ports.txt" ]; then
            output_diff "REMOVED LISTENING PORTS" "$(cat "$TEMP_DIR/removed_ports.txt")"
        fi
    fi
    
    # Also provide a more human-readable format that focuses on the actual services
    # Extract just protocol, address, and port number separately for clarity
    # Auto-detect format for each file

    # Process backup file
    if head -1 "$backup_file" 2>/dev/null | grep -q "Netid"; then
        # ss format - field 5 is local address:port
        grep "LISTEN" "$backup_file" 2>/dev/null | awk '{
            addr_port = $5
            n = split(addr_port, parts, ":")
            port = parts[n]
            addr = substr(addr_port, 1, length(addr_port) - length(port) - 1)
            printf "%-10s %-30s %-10s\n", $1, addr, port
        }' | sort -k3 -n > "$TEMP_DIR/backup_services.txt" || true
    else
        # netstat format - field 4 is local address:port
        grep "LISTEN" "$backup_file" 2>/dev/null | awk '{
            addr_port = $4
            n = split(addr_port, parts, ":")
            port = parts[n]
            addr = substr(addr_port, 1, length(addr_port) - length(port) - 1)
            printf "%-10s %-30s %-10s\n", $1, addr, port
        }' | sort -k3 -n > "$TEMP_DIR/backup_services.txt" || true
    fi

    # Process current file
    if head -1 "$current_file" 2>/dev/null | grep -q "Netid"; then
        # ss format - field 5 is local address:port
        grep "LISTEN" "$current_file" 2>/dev/null | awk '{
            addr_port = $5
            n = split(addr_port, parts, ":")
            port = parts[n]
            addr = substr(addr_port, 1, length(addr_port) - length(port) - 1)
            printf "%-10s %-30s %-10s\n", $1, addr, port
        }' | sort -k3 -n > "$TEMP_DIR/current_services.txt" || true
    else
        # netstat format - field 4 is local address:port
        grep "LISTEN" "$current_file" 2>/dev/null | awk '{
            addr_port = $4
            n = split(addr_port, parts, ":")
            port = parts[n]
            addr = substr(addr_port, 1, length(addr_port) - length(port) - 1)
            printf "%-10s %-30s %-10s\n", $1, addr, port
        }' | sort -k3 -n > "$TEMP_DIR/current_services.txt" || true
    fi
    
    # Perform diff on the service details if files were created
    if [ -s "$TEMP_DIR/backup_services.txt" ] && [ -s "$TEMP_DIR/current_services.txt" ]; then
        service_diff=$(diff -u "$TEMP_DIR/backup_services.txt" "$TEMP_DIR/current_services.txt" 2>/dev/null)
        if [ $? -ne 0 ]; then
            # Add header to make output clearer
            echo "Format: PROTOCOL  ADDRESS                        PORT" > "$TEMP_DIR/service_diff_header.txt"
            echo "---" >> "$TEMP_DIR/service_diff_header.txt"
            echo "$service_diff" >> "$TEMP_DIR/service_diff_header.txt"
            output_diff "DETAILED PORT BREAKDOWN" "$(cat "$TEMP_DIR/service_diff_header.txt")"
        fi
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
diff_connections() {
    local system_type="$1"
    local current_file="$TEMP_DIR/current/network_connections.txt"

    # Find the backup file using the fallback logic
    local backup_file=$(find_backup_file "$system_type" "network_connections.txt")

    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log "ERROR" "Backup connection file not found for system type: $system_type"
        log "ERROR" "Searched in: $BACKUP_ROOT/$system_type/latest/ and $BACKUP_ROOT/all/latest/"
        output_diff "NETWORK CONNECTIONS" "ERROR: Connection backup file not found.
  Searched in: $BACKUP_ROOT/$system_type/latest/system_info/ and $BACKUP_ROOT/all/latest/system_info/
  Fix: Run 'just backup $system_type' or 'just backup all' first."
        return 1
    fi

    if [ ! -f "$current_file" ]; then
        log "ERROR" "Current connection snapshot not found: $current_file"
        output_diff "NETWORK CONNECTIONS" "ERROR: Failed to generate current connection snapshot."
        return 1
    fi

    # Process both files to standardize output
    # Extract protocol, state, and address information
    # Auto-detect format: ss uses fields 1,2,5,6 while netstat uses 1,4,5,6

    # Process backup file
    if head -1 "$backup_file" 2>/dev/null | grep -q "Netid"; then
        # ss format
        grep -E "LISTEN|ESTAB|SYN|TIME_WAIT" "$backup_file" 2>/dev/null | awk '{print $1, $2, $5, $6}' | sort > "$TEMP_DIR/backup_connections.processed" || true
    else
        # netstat format - field 4 is Local Address, field 5 is Foreign Address, field 6 is State
        grep -E "LISTEN|ESTAB|SYN|TIME_WAIT" "$backup_file" 2>/dev/null | awk '{print $1, $6, $4, $5}' | sort > "$TEMP_DIR/backup_connections.processed" || true
    fi

    # Process current file
    if head -1 "$current_file" 2>/dev/null | grep -q "Netid"; then
        # ss format
        grep -E "LISTEN|ESTAB|SYN|TIME_WAIT" "$current_file" 2>/dev/null | awk '{print $1, $2, $5, $6}' | sort > "$TEMP_DIR/current_connections.processed" || true
    else
        # netstat format
        grep -E "LISTEN|ESTAB|SYN|TIME_WAIT" "$current_file" 2>/dev/null | awk '{print $1, $6, $4, $5}' | sort > "$TEMP_DIR/current_connections.processed" || true
    fi

    # Perform diff
    if command_exists colordiff && [ "$COLOR" = true ]; then
        diff_result=$(colordiff -u "$TEMP_DIR/backup_connections.processed" "$TEMP_DIR/current_connections.processed" 2>/dev/null)
    else
        diff_result=$(diff -u "$TEMP_DIR/backup_connections.processed" "$TEMP_DIR/current_connections.processed" 2>/dev/null)
    fi

    # Output results
    if [ -z "$diff_result" ]; then
        output_diff "NETWORK CONNECTIONS" "No changes detected"
    else
        output_diff "NETWORK CONNECTIONS" "$diff_result"

        # Write diff result to file for further processing
        echo "$diff_result" > "$TEMP_DIR/connections_diff.txt"

        # Show summary of new and removed connections
        grep "^+" "$TEMP_DIR/connections_diff.txt" | grep -v "^+++" | sed 's/^+//' > "$TEMP_DIR/added_connections.txt" 2>/dev/null || true
        grep "^-" "$TEMP_DIR/connections_diff.txt" | grep -v "^---" | sed 's/^-//' > "$TEMP_DIR/removed_connections.txt" 2>/dev/null || true

        if [ -s "$TEMP_DIR/added_connections.txt" ]; then
            output_diff "NEW CONNECTIONS" "$(cat "$TEMP_DIR/added_connections.txt")"
        fi

        if [ -s "$TEMP_DIR/removed_connections.txt" ]; then
            output_diff "CLOSED CONNECTIONS" "$(cat "$TEMP_DIR/removed_connections.txt")"
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
