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
  security      Backup security-critical files (STIG compliance)
  network       Backup network configurations
  firewall      Backup firewall rules
  services      Backup service configurations
  database      Backup database (MySQL/PostgreSQL)
  web           Backup web server configurations
  audit         Backup audit logs and compliance data
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
            # CCDC-focused backup: only critical files, not entire home directories
            # User shell configs for persistence detection
            source_dirs="/etc /var/spool/cron /var/log/audit /root/.ssh"

            # Add user SSH keys and shell profiles (not all dotfiles)
            if [ -d "/home" ]; then
                for user_home in /home/*; do
                    if [ -d "$user_home" ]; then
                        # SSH keys (persistence/incident response)
                        if [ -d "$user_home/.ssh" ]; then
                            source_dirs="$source_dirs $user_home/.ssh"
                        fi
                        # Shell profiles (persistence detection)
                        if [ -f "$user_home/.bashrc" ]; then
                            source_dirs="$source_dirs $user_home/.bashrc"
                        fi
                        if [ -f "$user_home/.bash_profile" ]; then
                            source_dirs="$source_dirs $user_home/.bash_profile"
                        fi
                        if [ -f "$user_home/.profile" ]; then
                            source_dirs="$source_dirs $user_home/.profile"
                        fi
                        if [ -f "$user_home/.zshrc" ]; then
                            source_dirs="$source_dirs $user_home/.zshrc"
                        fi
                    fi
                done
            fi
            ;;
        "security")
            # STIG and security-critical files
            # Note: Logging moved outside this function to avoid capturing log output as source_dirs

            # Authentication and authorization
            if [ -f "/etc/passwd" ]; then source_dirs="$source_dirs /etc/passwd"; fi
            if [ -f "/etc/shadow" ]; then source_dirs="$source_dirs /etc/shadow"; fi
            if [ -f "/etc/group" ]; then source_dirs="$source_dirs /etc/group"; fi
            if [ -f "/etc/gshadow" ]; then source_dirs="$source_dirs /etc/gshadow"; fi
            if [ -f "/etc/security/opasswd" ]; then source_dirs="$source_dirs /etc/security/opasswd"; fi

            # PAM configuration
            if [ -d "/etc/pam.d" ]; then source_dirs="$source_dirs /etc/pam.d"; fi
            if [ -d "/etc/security" ]; then source_dirs="$source_dirs /etc/security"; fi

            # SSH configuration
            if [ -d "/etc/ssh" ]; then source_dirs="$source_dirs /etc/ssh"; fi
            if [ -d "/root/.ssh" ]; then source_dirs="$source_dirs /root/.ssh"; fi

            # Sudo configuration
            if [ -f "/etc/sudoers" ]; then source_dirs="$source_dirs /etc/sudoers"; fi
            if [ -d "/etc/sudoers.d" ]; then source_dirs="$source_dirs /etc/sudoers.d"; fi

            # SELinux configuration
            if [ -d "/etc/selinux" ]; then source_dirs="$source_dirs /etc/selinux"; fi

            # AppArmor configuration
            if [ -d "/etc/apparmor.d" ]; then source_dirs="$source_dirs /etc/apparmor.d"; fi
            if [ -d "/etc/apparmor" ]; then source_dirs="$source_dirs /etc/apparmor"; fi

            # Audit configuration
            if [ -d "/etc/audit" ]; then source_dirs="$source_dirs /etc/audit"; fi
            if [ -d "/etc/audisp" ]; then source_dirs="$source_dirs /etc/audisp"; fi

            # Login/session configuration
            if [ -f "/etc/login.defs" ]; then source_dirs="$source_dirs /etc/login.defs"; fi
            if [ -f "/etc/securetty" ]; then source_dirs="$source_dirs /etc/securetty"; fi
            if [ -d "/etc/profile.d" ]; then source_dirs="$source_dirs /etc/profile.d"; fi
            if [ -f "/etc/profile" ]; then source_dirs="$source_dirs /etc/profile"; fi
            if [ -f "/etc/bashrc" ]; then source_dirs="$source_dirs /etc/bashrc"; fi
            if [ -f "/etc/bash.bashrc" ]; then source_dirs="$source_dirs /etc/bash.bashrc"; fi

            # System integrity tools
            if [ -d "/etc/aide" ]; then source_dirs="$source_dirs /etc/aide"; fi
            if [ -d "/etc/tripwire" ]; then source_dirs="$source_dirs /etc/tripwire"; fi

            # CA certificates and crypto
            if [ -d "/etc/pki" ]; then source_dirs="$source_dirs /etc/pki"; fi
            if [ -d "/etc/ssl" ]; then source_dirs="$source_dirs /etc/ssl"; fi
            if [ -d "/usr/local/share/ca-certificates" ]; then source_dirs="$source_dirs /usr/local/share/ca-certificates"; fi

            # Trim leading space
            source_dirs=$(echo "$source_dirs" | sed 's/^ //')
            ;;
        "audit")
            # Audit logs and compliance data
            # Note: Logging moved outside this function to avoid capturing log output as source_dirs

            # Audit logs
            if [ -d "/var/log/audit" ]; then source_dirs="$source_dirs /var/log/audit"; fi

            # System logs
            if [ -f "/var/log/auth.log" ]; then source_dirs="$source_dirs /var/log/auth.log"; fi
            if [ -f "/var/log/secure" ]; then source_dirs="$source_dirs /var/log/secure"; fi
            if [ -f "/var/log/messages" ]; then source_dirs="$source_dirs /var/log/messages"; fi
            if [ -f "/var/log/syslog" ]; then source_dirs="$source_dirs /var/log/syslog"; fi

            # Failed login attempts
            if [ -f "/var/log/faillog" ]; then source_dirs="$source_dirs /var/log/faillog"; fi
            if [ -f "/var/log/btmp" ]; then source_dirs="$source_dirs /var/log/btmp"; fi
            if [ -f "/var/log/wtmp" ]; then source_dirs="$source_dirs /var/log/wtmp"; fi
            if [ -f "/var/log/lastlog" ]; then source_dirs="$source_dirs /var/log/lastlog"; fi

            # Trim leading space
            source_dirs=$(echo "$source_dirs" | sed 's/^ //')
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
            # CCDC: Only config files, not actual database data
            # Database data can be huge and isn't needed for quick config restore
            source_dirs="/etc/mysql /etc/postgresql"
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

    # BusyBox-compatible last command (no -n flag support)
    if is_busybox; then
        # BusyBox last doesn't support -n, use head instead
        log "INFO" "Using BusyBox-compatible last command"
        last 2>/dev/null | head -20 > "$dump_dir/recent_logins.txt" || true
    else
        # Full last command supports -n
        last -n 20 > "$dump_dir/recent_logins.txt" 2>/dev/null || true
    fi
    
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

    
    # Additional specialized information based on system type
    case "$system" in
        "security"|"all")
            log "INFO" "Capturing security-critical system state"

            # SUID/SGID files list
            log "INFO" "Finding SUID/SGID binaries"
            # Use fd if available, fallback to find
            if command_exists fd; then
                fd --one-file-system --type f --perm u+s,g+s --exec ls -la > "$dump_dir/suid_sgid_files.txt" 2>/dev/null || true
            else
                find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -exec ls -la {} \; > "$dump_dir/suid_sgid_files.txt" 2>/dev/null || true
            fi

            # World-writable files
            log "INFO" "Finding world-writable files"
            if command_exists fd; then
                fd --one-file-system --type f --perm o+w --exec ls -la > "$dump_dir/world_writable_files.txt" 2>/dev/null || true
            else
                find / -xdev -type f -perm -0002 -exec ls -la {} \; > "$dump_dir/world_writable_files.txt" 2>/dev/null || true
            fi

            # World-writable directories
            if command_exists fd; then
                fd --one-file-system --type d --perm o+w --exec ls -lad > "$dump_dir/world_writable_dirs.txt" 2>/dev/null || true
            else
                find / -xdev -type d -perm -0002 -exec ls -lad {} \; > "$dump_dir/world_writable_dirs.txt" 2>/dev/null || true
            fi

            # Files with no owner
            log "INFO" "Finding files with no owner"
            if command_exists fd; then
                fd --one-file-system --no-ignore --owner ':nouser' --exec ls -la > "$dump_dir/unowned_files.txt" 2>/dev/null || true
            else
                find / -xdev \( -nouser -o -nogroup \) -exec ls -la {} \; > "$dump_dir/unowned_files.txt" 2>/dev/null || true
            fi

            # File capabilities
            if command_exists getcap; then
                log "INFO" "Capturing file capabilities"
                getcap -r / 2>/dev/null > "$dump_dir/file_capabilities.txt" || true
            fi

            # SELinux status and contexts
            if command_exists getenforce; then
                log "INFO" "Capturing SELinux status"
                getenforce > "$dump_dir/selinux_status.txt"
                if command_exists sestatus; then
                    sestatus > "$dump_dir/selinux_detailed.txt"
                fi
                # SELinux contexts for key files
                ls -Z /etc/passwd /etc/shadow /etc/ssh/sshd_config > "$dump_dir/selinux_contexts.txt" 2>/dev/null || true
            fi

            # AppArmor status
            if command_exists aa-status; then
                log "INFO" "Capturing AppArmor status"
                aa-status > "$dump_dir/apparmor_status.txt" 2>/dev/null || true
            fi

            # Audit daemon status
            if command_exists auditctl; then
                log "INFO" "Capturing audit rules"
                auditctl -l > "$dump_dir/audit_rules.txt" 2>/dev/null || true
                auditctl -s > "$dump_dir/audit_status.txt" 2>/dev/null || true
            fi

            # Password policy
            if [ -f "/etc/login.defs" ]; then
                grep -E "PASS_MAX_DAYS|PASS_MIN_DAYS|PASS_MIN_LEN|PASS_WARN_AGE" /etc/login.defs > "$dump_dir/password_policy.txt" 2>/dev/null || true
            fi

            # Failed login attempts
            if command_exists faillog; then
                faillog -a > "$dump_dir/failed_logins.txt" 2>/dev/null || true
            fi

            # Last logins
            if command_exists lastlog; then
                lastlog > "$dump_dir/last_logins.txt" 2>/dev/null || true
            fi

            # Currently logged in users with details
            w > "$dump_dir/current_users_detailed.txt" 2>/dev/null || true

            # Sudo access
            log "INFO" "Capturing sudo access configuration"
            if [ -f "/etc/sudoers" ]; then
                # Parse sudoers safely
                grep -v '^#' /etc/sudoers | grep -v '^$' > "$dump_dir/sudoers_active.txt" 2>/dev/null || true
            fi

            # SSH authorized keys for all users
            log "INFO" "Collecting SSH authorized keys"
            # Check root first
            if [ -f "/root/.ssh/authorized_keys" ]; then
                echo "=== root ===" >> "$dump_dir/ssh_authorized_keys.txt"
                cat /root/.ssh/authorized_keys >> "$dump_dir/ssh_authorized_keys.txt" 2>/dev/null || true
                echo "" >> "$dump_dir/ssh_authorized_keys.txt"
            fi
            # Check home directories (BusyBox-compatible)
            if [ -d "/home" ]; then
                for user_home in /home/*; do
                    if [ -d "$user_home" ] && [ -d "$user_home/.ssh" ]; then
                        username=$(basename "$user_home")
                        if [ -f "$user_home/.ssh/authorized_keys" ]; then
                            echo "=== $username ===" >> "$dump_dir/ssh_authorized_keys.txt"
                            cat "$user_home/.ssh/authorized_keys" >> "$dump_dir/ssh_authorized_keys.txt" 2>/dev/null || true
                            echo "" >> "$dump_dir/ssh_authorized_keys.txt"
                        fi
                    fi
                done
            fi

            # Checksums of critical system binaries
            log "INFO" "Computing checksums of critical binaries"
            if command_exists sha256sum; then
                # Use fd if available for better performance
                if command_exists fd; then
                    for dir in /bin /sbin /usr/bin /usr/sbin; do
                        if [ -d "$dir" ]; then
                            fd --type f --base-directory "$dir" --exec sha256sum 2>/dev/null >> "$dump_dir/binary_checksums.txt" || true
                        fi
                    done
                else
                    # BusyBox-compatible fallback
                    for dir in /bin /sbin /usr/bin /usr/sbin; do
                        if [ -d "$dir" ]; then
                            find "$dir" -type f 2>/dev/null | while read -r file; do
                                sha256sum "$file" 2>/dev/null || true
                            done >> "$dump_dir/binary_checksums.txt"
                        fi
                    done
                fi
            elif command_exists md5sum; then
                if command_exists fd; then
                    for dir in /bin /sbin /usr/bin /usr/sbin; do
                        if [ -d "$dir" ]; then
                            fd --type f --base-directory "$dir" --exec md5sum 2>/dev/null >> "$dump_dir/binary_checksums.txt" || true
                        fi
                    done
                else
                    for dir in /bin /sbin /usr/bin /usr/sbin; do
                        if [ -d "$dir" ]; then
                            find "$dir" -type f 2>/dev/null | while read -r file; do
                                md5sum "$file" 2>/dev/null || true
                            done >> "$dump_dir/binary_checksums.txt"
                        fi
                    done
                fi
            fi

            # Loaded kernel modules
            log "INFO" "Capturing loaded kernel modules"
            lsmod > "$dump_dir/loaded_modules.txt" 2>/dev/null || true

            # Kernel parameters
            if command_exists sysctl; then
                sysctl -a > "$dump_dir/kernel_parameters.txt" 2>/dev/null || true
            fi

            # File ACLs for critical directories
            if command_exists getfacl; then
                log "INFO" "Capturing file ACLs for critical directories"
                getfacl -R /etc 2>/dev/null > "$dump_dir/etc_acls.txt" || true
            fi

            # Capture systemd security settings
            if command_exists systemd-analyze; then
                log "INFO" "Capturing systemd security analysis"
                systemd-analyze security > "$dump_dir/systemd_security.txt" 2>/dev/null || true
            fi

            # For "all" backup, continue to network section
            # (network section will be processed next in the case statement)
            ;;
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
                # Using -U postgres instead of sudo
                psql -U postgres -c "\l" > "$dump_dir/postgres_databases.txt" 2>/dev/null || true
                psql -U postgres -c "\du" > "$dump_dir/postgres_users.txt" 2>/dev/null || true
            fi
            ;;
        "audit")
            log "INFO" "Capturing audit and compliance information"

            # Audit logs analysis
            if command_exists aureport; then
                log "INFO" "Generating audit reports"
                aureport --summary > "$dump_dir/audit_summary.txt" 2>/dev/null || true
                aureport --auth > "$dump_dir/audit_auth.txt" 2>/dev/null || true
                aureport --login > "$dump_dir/audit_logins.txt" 2>/dev/null || true
                aureport --failed > "$dump_dir/audit_failed.txt" 2>/dev/null || true
            fi

            # Authentication attempts from auth.log
            if [ -f "/var/log/auth.log" ]; then
                grep "Failed password" /var/log/auth.log | tail -100 > "$dump_dir/recent_failed_auth.txt" 2>/dev/null || true
                grep "Accepted password" /var/log/auth.log | tail -100 > "$dump_dir/recent_successful_auth.txt" 2>/dev/null || true
            elif [ -f "/var/log/secure" ]; then
                grep "Failed password" /var/log/secure | tail -100 > "$dump_dir/recent_failed_auth.txt" 2>/dev/null || true
                grep "Accepted password" /var/log/secure | tail -100 > "$dump_dir/recent_successful_auth.txt" 2>/dev/null || true
            fi

            # Sudo usage
            if [ -f "/var/log/auth.log" ]; then
                grep "sudo:" /var/log/auth.log | tail -100 > "$dump_dir/sudo_usage.txt" 2>/dev/null || true
            elif [ -f "/var/log/secure" ]; then
                grep "sudo:" /var/log/secure | tail -100 > "$dump_dir/sudo_usage.txt" 2>/dev/null || true
            fi

            # Login history
            if is_busybox; then
                # BusyBox last doesn't support -F or -n flags
                last 2>/dev/null | head -100 > "$dump_dir/login_history.txt" || true
            else
                last -F -n 100 > "$dump_dir/login_history.txt" 2>/dev/null || true
            fi

            # Failed login history
            if is_busybox; then
                # BusyBox lastb doesn't support -F or -n flags
                lastb 2>/dev/null | head -100 > "$dump_dir/failed_login_history.txt" || true
            else
                lastb -F -n 100 > "$dump_dir/failed_login_history.txt" 2>/dev/null || true
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

# Verify backup was created
TIMESTAMP=$(date +%Y%m%d)
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"
if [ -d "$BACKUP_PATH" ]; then
    log "INFO" "Backup verification: Backup directory exists at $BACKUP_PATH"

    # Count files in backup
    if command_exists fd; then
        FILE_COUNT=$(fd --type f --base-directory "$BACKUP_PATH" 2>/dev/null | wc -l)
    else
        FILE_COUNT=$(find "$BACKUP_PATH" -type f 2>/dev/null | wc -l)
    fi
    log "INFO" "Backup verification: $FILE_COUNT files backed up"

    # Check backup size
    BACKUP_SIZE=$(du -sh "$BACKUP_PATH" 2>/dev/null | cut -f1)
    log "INFO" "Backup verification: Backup size is $BACKUP_SIZE"

    # Verify manifest exists
    if [ -f "$BACKUP_PATH/manifest.txt" ]; then
        log "INFO" "Backup verification: Manifest file created successfully"
    else
        log "WARNING" "Backup verification: Manifest file missing"
    fi

    # Verify system_info directory exists
    if [ -d "$BACKUP_PATH/system_info" ]; then
        if command_exists fd; then
            INFO_FILES=$(fd --type f --base-directory "$BACKUP_PATH/system_info" 2>/dev/null | wc -l)
        else
            INFO_FILES=$(find "$BACKUP_PATH/system_info" -type f 2>/dev/null | wc -l)
        fi
        log "INFO" "Backup verification: $INFO_FILES system info files captured"
    else
        log "WARNING" "Backup verification: system_info directory missing"
    fi
else
    log "ERROR" "Backup verification: Backup directory not found at $BACKUP_PATH"
    exit 1
fi

log "INFO" "Backup operation completed successfully"
log "INFO" "Backup location: $BACKUP_PATH"
log "INFO" "Latest symlink: $BACKUP_DIR/latest"

exit 0
