#!/bin/sh
# Exit on errors
set -e

# Default configuration - these will be overridden by environment variables
# which can be set in the justfile
CONFIG_FILE="${KK_CONFIG_DIR:-/etc}/backup-config.conf"
LOG_FILE="${KK_LOG_DIR:-/var/log}/system-backup.log"
VERBOSE=false
DRY_RUN=false
EXCLUDE_PATTERNS="/tmp/* /var/tmp/* /proc/* /sys/* /run/* /dev/* /mnt/* /media/* /lost+found"
BASE_DIR="${KK_BASE_DIR:-/opt/keyboard_kowboys}"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: This script must be run as root"
        exit 1
    fi
}

# Function to display help
show_help() {
    cat << EOF
Optimized System Backup Solution using rsync

Usage: $0 [OPTIONS] <system_name> <backup_directory>

Systems:
  all           Backup all system configurations
  network       Backup network configurations
  firewall      Backup firewall rules
  services      Backup service configurations
  database      Backup database (MySQL/PostgreSQL)
  web           Backup web server configurations
  custom        Custom backup defined in configuration file

Options:
  -h, --help                   Show this help message
  -c, --config FILE            Use specified config file (default: $CONFIG_FILE)
  -l, --log FILE               Log file location (default: $LOG_FILE)
  -v, --verbose                Enable verbose output
  -d, --dry-run                Perform a trial run with no changes made
  -x, --exclude PATTERN        Exclude files/directories matching pattern

Environment Variables:
  KK_BASE_DIR                  Base directory (default: /opt/keyboard_kowboys)
  KK_CONFIG_DIR                Configuration directory (default: $BASE_DIR/configs)
  KK_LOG_DIR                   Log directory (default: $BASE_DIR/logs)

Examples:
  $0 all $BASE_DIR/backups
  $0 -v network $BASE_DIR/backups/network
  $0 --dry-run firewall $BASE_DIR/backups/firewall

EOF
    exit 0
}

# Function to log messages
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [ "$VERBOSE" = true ] || [ "$level" = "ERROR" ]; then
        echo "[$level] $message"
    fi
}

# Function to check required dependencies
check_dependencies() {
    # Check for rsync
    if ! command_exists rsync; then
        log "ERROR" "rsync is required but not installed. Please install rsync first."
        echo "To install rsync:"
        echo "  - Debian/Ubuntu: sudo apt-get install rsync"
        echo "  - RHEL/CentOS: sudo yum install rsync"
        echo "  - Alpine: apk add rsync"
        exit 1
    fi
    
    # Check for fd (optional)
    if command_exists fd; then
        log "INFO" "Using fd for faster file operations"
        USE_FD=true
    else
        USE_FD=false
    fi
}

# Function to create backup filename
get_backup_filename() {
    local system="$1"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local hostname=$(hostname -s)
    
    echo "${system}-${hostname}-${timestamp}"
}

# Function to get source directories for a system type
get_source_dirs() {
    local system="$1"
    local source_dirs=""
    
    case "$system" in
        "all")
            source_dirs="/etc /home/*/.??* /var/spool/cron"
            ;;
        "network")
            # Check for files/directories before adding them
            if [ -d "/etc/network" ]; then source_dirs="$source_dirs /etc/network"; fi
            if [ -d "/etc/netplan" ]; then source_dirs="$source_dirs /etc/netplan"; fi
            if [ -f "/etc/hosts" ]; then source_dirs="$source_dirs /etc/hosts"; fi
            if [ -f "/etc/resolv.conf" ]; then source_dirs="$source_dirs /etc/resolv.conf"; fi
            if [ -f "/etc/hostname" ]; then source_dirs="$source_dirs /etc/hostname"; fi
            if [ -f "/etc/networks" ]; then source_dirs="$source_dirs /etc/networks"; fi
            if [ -d "/etc/NetworkManager" ]; then source_dirs="$source_dirs /etc/NetworkManager"; fi
            
            # Trim leading space if present
            source_dirs=$(echo "$source_dirs" | sed 's/^ //')
            ;;
        "firewall")
            # Check for files/directories before adding them
            if [ -d "/etc/iptables" ]; then source_dirs="$source_dirs /etc/iptables"; fi
            if [ -f "/etc/nftables.conf" ]; then source_dirs="$source_dirs /etc/nftables.conf"; fi
            if [ -d "/etc/ufw" ]; then source_dirs="$source_dirs /etc/ufw"; fi
            if [ -d "/etc/firewalld" ]; then source_dirs="$source_dirs /etc/firewalld"; fi
            
            # Trim leading space if present
            source_dirs=$(echo "$source_dirs" | sed 's/^ //')
            ;;
        "services")
            source_dirs="/etc/systemd /etc/init.d /etc/init /etc/cron* /etc/logrotate.d"
            ;;
        "database")
            source_dirs="/etc/mysql /etc/postgresql /var/lib/mysql /var/lib/postgresql"
            ;;
        "web")
            source_dirs="/etc/apache2 /etc/nginx /etc/php /etc/letsencrypt"
            ;;
        "custom")
            if [ -f "$CONFIG_FILE" ]; then
                . "$CONFIG_FILE"
                if [ -n "$CUSTOM_SOURCE_DIRS" ]; then
                    source_dirs="$CUSTOM_SOURCE_DIRS"
                else
                    log "ERROR" "CUSTOM_SOURCE_DIRS not defined in config file"
                    exit 1
                fi
            else
                log "ERROR" "Config file not found for custom backup"
                exit 1
            fi
            ;;
        *)
            # For specific services, try to find relevant directories
            if [ -d "/etc/$system" ]; then
                source_dirs="/etc/$system"
            fi
            if [ -f "/etc/systemd/system/$system.service" ]; then
                source_dirs="$source_dirs /etc/systemd/system/$system.service"
            fi
            if [ -d "/etc/default/$system" ]; then
                source_dirs="$source_dirs /etc/default/$system"
            fi
            ;;
    esac
    
    echo "$source_dirs"
}

# Function to perform a system dump for metadata
perform_system_dump() {
    local system="$1"
    local backup_path="$2"
    local dump_dir="$backup_path/system_info"
    
    log "INFO" "Creating system information snapshot in $dump_dir"
    mkdir -p "$dump_dir"
    
    # Common system information to gather for all backup types
    log "INFO" "Capturing basic system information"
    uname -a > "$dump_dir/kernel_info.txt"
    df -h > "$dump_dir/disk_usage.txt"
    mount > "$dump_dir/mounts.txt"
    
    # Network connection information (for all backup types)
    log "INFO" "Capturing current network connections"
    # Check which network tool is available and use it
    if command_exists ss; then
        log "INFO" "Using ss to capture network connections"
        ss -tunapl > "$dump_dir/network_connections.txt"
        ss -tuln > "$dump_dir/listening_ports.txt"
    elif command_exists netstat; then
        log "INFO" "Using netstat to capture network connections"
        netstat -tunapl > "$dump_dir/network_connections.txt"
        netstat -tuln > "$dump_dir/listening_ports.txt"
    else
        log "WARNING" "Neither ss nor netstat found, skipping network connection backup"
    fi
    
    # Running processes (for all backup types)
    log "INFO" "Capturing current processes"
    ps aux > "$dump_dir/processes.txt"
    
    # User information
    log "INFO" "Capturing user information"
    who > "$dump_dir/logged_users.txt"
    last -n 20 > "$dump_dir/recent_logins.txt"
    
    # Service information
    log "INFO" "Capturing service information"
    if command_exists systemctl; then
        systemctl list-units --type=service --state=active > "$dump_dir/active_services.txt"
        systemctl list-unit-files --type=service > "$dump_dir/service_status.txt"
    elif command_exists service; then
        service --status-all > "$dump_dir/service_status.txt"
    fi
    
    # Package information
    log "INFO" "Capturing package information"
    if command_exists dpkg; then
        dpkg --get-selections > "$dump_dir/packages.list"
    elif command_exists rpm; then
        rpm -qa | sort > "$dump_dir/packages.list"
    elif command_exists nix-env; then
        nix-env -q > "$dump_dir/packages.list"
    fi
    
    # Additional specialized information based on system type
    case "$system" in
        "network")
            log "INFO" "Capturing additional network information"
            ip addr > "$dump_dir/ip_addr.txt"
            ip route > "$dump_dir/ip_route.txt"
            ip rule list > "$dump_dir/ip_rules.txt"
            
            # Additional detailed network information
            if command_exists ip; then
                ip neigh show > "$dump_dir/arp_cache.txt" # ARP cache
            elif command_exists arp; then
                arp -an > "$dump_dir/arp_cache.txt"
            fi
            
            # DNS resolution configuration
            cp /etc/resolv.conf "$dump_dir/resolv.conf" 2>/dev/null || true
            
            # Get active network interfaces statistics
            if command_exists ifconfig; then
                ifconfig -a > "$dump_dir/interface_details.txt"
            elif command_exists ip; then
                ip -s link > "$dump_dir/interface_details.txt"
            fi
            
            # Capture routing table
            netstat -rn > "$dump_dir/routing_table.txt" 2>/dev/null || ip route show > "$dump_dir/routing_table.txt"
            
            # Capture socket statistics
            if command_exists ss; then
                ss -s > "$dump_dir/socket_statistics.txt"
            fi
            ;;
        "firewall")
            log "INFO" "Capturing detailed firewall information"
            if command_exists iptables-save; then
                iptables-save > "$dump_dir/iptables.rules"
                if command_exists ip6tables-save; then
                    ip6tables-save > "$dump_dir/ip6tables.rules"
                fi
            fi
            
            if command_exists nft; then
                nft list ruleset > "$dump_dir/nftables.rules"
            fi
            
            if command_exists ufw; then
                ufw status verbose > "$dump_dir/ufw_status.txt"
            fi
            
            if command_exists firewall-cmd; then
                firewall-cmd --list-all > "$dump_dir/firewalld_list.txt"
                firewall-cmd --permanent --list-all > "$dump_dir/firewalld_permanent.txt"
            fi
            ;;
        "services")
            log "INFO" "Capturing detailed service information"
            # Already captured the basics above
            # Add more detailed service info
            if command_exists systemctl; then
                systemctl list-dependencies > "$dump_dir/service_dependencies.txt"
                systemctl list-units --failed > "$dump_dir/failed_services.txt"
            fi
            
            # Cron jobs
            if [ -f "/etc/crontab" ]; then
                cp /etc/crontab "$dump_dir/crontab"
            fi
            
            # Capture journalctl boot log
            if command_exists journalctl; then
                journalctl -b -n 1000 > "$dump_dir/boot_log.txt"
            fi
            ;;
        "database")
            log "INFO" "Capturing database information"
            # Database status info will depend on the database type
            if command_exists mysql && [ -f "$CONFIG_FILE" ]; then
                . "$CONFIG_FILE"
                if [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_PASSWORD" ]; then
                    mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SHOW DATABASES;" > "$dump_dir/mysql_databases.txt"
                    mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SHOW VARIABLES;" > "$dump_dir/mysql_variables.txt"
                    mysql -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SHOW STATUS;" > "$dump_dir/mysql_status.txt"
                fi
            fi
            
            if command_exists psql; then
                sudo -u postgres psql -c "\l" > "$dump_dir/postgres_databases.txt" 2>/dev/null || true
                sudo -u postgres psql -c "\du" > "$dump_dir/postgres_users.txt" 2>/dev/null || true
            fi
            ;;
    esac
    
    # Create a system snapshot timestamp
    date > "$dump_dir/snapshot_time.txt"
    log "INFO" "System information snapshot completed"
}

# Function to perform backup using rsync
perform_backup() {
    local system="$1"
    local backup_dir="$2"
    local timestamp=$(date +%Y%m%d)
    local latest_link="$backup_dir/latest"
    local backup_path="$backup_dir/$timestamp"
    local source_dirs=$(get_source_dirs "$system")
    
    if [ -z "$source_dirs" ]; then
        log "WARNING" "No source directories identified for system: $system"
        log "INFO" "Will continue with system info dump only"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "Dry run: would backup from $source_dirs to $backup_path"
        return 0
    fi
    
    # Create backup directory if it doesn't exist
    mkdir -p "$backup_path"
    
    log "INFO" "Starting backup of $system to $backup_path"
    
    # Build exclude options
    local exclude_opts=""
    for pattern in $EXCLUDE_PATTERNS; do
        exclude_opts="$exclude_opts --exclude=$pattern"
    done
    
    # Process each source directory if any were found
    if [ -n "$source_dirs" ]; then
        for src in $source_dirs; do
            # Skip if source doesn't exist
            if [ ! -e "$src" ]; then
                log "INFO" "Source does not exist, skipping: $src"
                continue
            fi
            
            # Get the base name for the destination
            local base_name=$(basename "$src")
            local dest_dir="$backup_path/$base_name"
            local dest_parent="$(dirname "$dest_dir")"
            
            # Create parent directories
            mkdir -p "$dest_parent"
            
            log "INFO" "Backing up $src to $dest_dir"
            
            # Determine if source is a file or directory
            if [ -d "$src" ]; then
                # Directory backup with trailing slash to copy contents
                if [ -d "$latest_link" ]; then
                    if [ -d "$latest_link/$base_name" ]; then
                        rsync -a --delete --one-file-system $exclude_opts \
                              --link-dest="$latest_link/$base_name" "$src/" "$dest_dir/" || \
                        log "WARNING" "rsync encountered issues with $src"
                    else
                        rsync -a --delete --one-file-system $exclude_opts \
                              "$src/" "$dest_dir/" || \
                        log "WARNING" "rsync encountered issues with $src"
                    fi
                else
                    rsync -a --delete --one-file-system $exclude_opts \
                          "$src/" "$dest_dir/" || \
                    log "WARNING" "rsync encountered issues with $src"
                fi
            else
                # Single file backup - create parent directory first
                mkdir -p "$dest_parent"
                
                if [ -d "$latest_link" ]; then
                    if [ -f "$latest_link/$base_name" ]; then
                        rsync -a $exclude_opts \
                              --link-dest="$latest_link/$base_name" "$src" "$dest_parent/" || \
                        log "WARNING" "rsync encountered issues with $src"
                    else
                        rsync -a $exclude_opts "$src" "$dest_parent/" || \
                        log "WARNING" "rsync encountered issues with $src"
                    fi
                else
                    rsync -a $exclude_opts "$src" "$dest_parent/" || \
                    log "WARNING" "rsync encountered issues with $src"
                fi
            fi
        done
    fi
    
    # Gather system info
    perform_system_dump "$system" "$backup_path"
    
    # Create a manifest file
    {
        echo "Backup System: Optimized System Backup Solution v3.0"
        echo "Date: $(date)"
        echo "System: $system"
        echo "Hostname: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo "Source Directories:"
        for src in $source_dirs; do
            echo "  - $src"
        done
    } > "$backup_path/manifest.txt"
    
    # Update the "latest" symlink
    rm -f "$latest_link"
    ln -sf "$timestamp" "$latest_link"
    
    log "INFO" "Backup completed successfully: $system to $backup_path"
}

# Parse command line arguments (POSIX-compliant way)
POSITIONAL=""
while [ $# -gt 0 ]; do
    key="$1"
    
    case $key in
        -h|--help)
            show_help
            ;;
        -c|--config)
            CONFIG_FILE="$2"
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
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -x|--exclude)
            if [ -z "$EXCLUDE_PATTERNS" ]; then
                EXCLUDE_PATTERNS="$2"
            else
                EXCLUDE_PATTERNS="$EXCLUDE_PATTERNS $2"
            fi
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

# Check if config file exists and load it
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# Check for required arguments
if [ $# -lt 2 ]; then
    log "ERROR" "Missing required arguments"
    show_help
fi

SYSTEM_NAME="$1"
BACKUP_DIR="$2"

# Check if running as root
check_root

# Initialize log file
touch "$LOG_FILE" || {
    echo "ERROR: Cannot write to log file $LOG_FILE"
    exit 1
}

# Log script start
log "INFO" "Starting Optimized System Backup Solution (v3.0)"
log "INFO" "System: $SYSTEM_NAME, Backup directory: $BACKUP_DIR"
log "INFO" "Using configuration from: $CONFIG_FILE"
log "INFO" "Logging to: $LOG_FILE"

# Check dependencies
check_dependencies

# Perform the backup
perform_backup "$SYSTEM_NAME" "$BACKUP_DIR"

exit 0
