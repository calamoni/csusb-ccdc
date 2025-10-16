#!/bin/sh
# POSIX-compliant persistence detection script
# Works on standard Linux and BusyBox systems
# Detects common backdoor persistence mechanisms

set -e

# Default configuration
BASE_DIR="${KK_BASE_DIR:-/opt/keyboard_kowboys}"
LOG_DIR="${KK_LOG_DIR:-$BASE_DIR/logs}"
BACKUP_DIR="${KK_BACKUP_DIR:-$BASE_DIR/backups}"
LOG_FILE="$LOG_DIR/persistence-check.log"
REPORT_FILE="$LOG_DIR/persistence-report-$(date +%Y%m%d-%H%M%S).txt"
VERBOSE=false
ISSUES_FOUND=0

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if running on BusyBox
is_busybox() {
    if command_exists busybox; then
        if busybox 2>/dev/null | head -1 | grep -q "BusyBox"; then
            return 0
        fi
    fi
    return 1
}

# Function to log messages
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true

    if [ "$VERBOSE" = true ] || [ "$level" = "ERROR" ] || [ "$level" = "WARNING" ]; then
        echo "[$level] $message"
    fi
}

# Function to report findings
report() {
    local severity="$1"
    local category="$2"
    local message="$3"

    echo "[$severity] $category: $message" >> "$REPORT_FILE"
    echo "[$severity] $category: $message"

    if [ "$severity" = "CRITICAL" ] || [ "$severity" = "HIGH" ]; then
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    log "$severity" "$category: $message"
}

# Function to check cron jobs
check_cron() {
    log "INFO" "Checking cron jobs for persistence mechanisms..."
    echo "" >> "$REPORT_FILE"
    echo "=== CRON JOBS ANALYSIS ===" >> "$REPORT_FILE"

    local cron_files_found=0

    # Check system crontabs
    # Check /etc/crontab (file)
    if [ -f "/etc/crontab" ]; then
        cron_files_found=$((cron_files_found + 1))
        log "INFO" "Analyzing /etc/crontab"
        echo "Found: /etc/crontab (file)" >> "$REPORT_FILE"

        # Look for suspicious patterns
        if grep -qE "curl|wget|nc|bash -i|/dev/tcp|base64|python -c|perl -e" /etc/crontab 2>/dev/null; then
            report "CRITICAL" "CRON" "Suspicious commands found in /etc/crontab"
            grep -E "curl|wget|nc|bash -i|/dev/tcp|base64|python -c|perl -e" /etc/crontab 2>/dev/null | head -3 >> "$REPORT_FILE"
        fi

        # Check for modifications
        if [ -f "$BACKUP_DIR/all/latest/etc/crontab" ]; then
            if ! diff -q /etc/crontab "$BACKUP_DIR/all/latest/etc/crontab" >/dev/null 2>&1; then
                report "HIGH" "CRON" "/etc/crontab has been modified since backup"
            fi
        fi
    else
        log "INFO" "/etc/crontab not found (may not exist on this system)"
        echo "Not found: /etc/crontab" >> "$REPORT_FILE"
    fi

    # Also check /etc/crontabs/ (directory) - used by some BusyBox systems
    # Note: This is different from user crontabs checked later
    if [ -d "/etc/crontabs" ]; then
        # Count system crontab files
        sys_cron_count=0
        for sys_cron in /etc/crontabs/*; do
            if [ -e "$sys_cron" ] && [ -f "$sys_cron" ]; then
                sys_cron_count=$((sys_cron_count + 1))
            fi
        done

        if [ $sys_cron_count -gt 0 ]; then
            log "INFO" "Found system crontabs in /etc/crontabs/"
            echo "Found: /etc/crontabs/ ($sys_cron_count system crontabs)" >> "$REPORT_FILE"

            # This will be checked in the user crontabs section below
            # Just note it here for visibility
        fi
    fi

    # Check cron directories
    for cron_dir in /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
        if [ -d "$cron_dir" ]; then
            log "INFO" "Scanning $cron_dir"

            # Count files in directory (BusyBox-compatible)
            file_count=0
            for cron_file in "$cron_dir"/*; do
                # Check if file exists (not just glob pattern)
                if [ -e "$cron_file" ]; then
                    file_count=$((file_count + 1))
                fi
            done

            if [ $file_count -eq 0 ]; then
                log "INFO" "$cron_dir is empty"
                echo "Found: $cron_dir (empty)" >> "$REPORT_FILE"
            else
                cron_files_found=$((cron_files_found + file_count))
                echo "Found: $cron_dir ($file_count files)" >> "$REPORT_FILE"

                # List all cron files
                for cron_file in "$cron_dir"/*; do
                    # Skip if glob didn't match anything
                    if [ ! -e "$cron_file" ]; then
                        continue
                    fi

                    if [ -f "$cron_file" ]; then
                        basename_file=$(basename "$cron_file")
                        log "INFO" "  Checking: $basename_file"

                        # Check for suspicious patterns
                        if grep -qE "curl|wget|nc|bash -i|/dev/tcp|base64|python -c|perl -e" "$cron_file" 2>/dev/null; then
                            report "CRITICAL" "CRON" "Suspicious commands in $cron_file"
                            echo "  Suspicious: $basename_file" >> "$REPORT_FILE"
                            grep -E "curl|wget|nc|bash -i|/dev/tcp|base64|python -c|perl -e" "$cron_file" 2>/dev/null | head -2 >> "$REPORT_FILE"
                        else
                            echo "  OK: $basename_file" >> "$REPORT_FILE"
                        fi
                    fi
                done
            fi
        else
            log "INFO" "$cron_dir not found"
            echo "Not found: $cron_dir" >> "$REPORT_FILE"
        fi
    done

    # Check user crontabs
    # Different systems use different locations:
    # - Standard Linux: /var/spool/cron/crontabs/
    # - Some Linux: /var/spool/cron/
    # - BusyBox/Alpine: /etc/crontabs/ or /var/spool/cron/crontabs/
    local user_cron_dirs="/var/spool/cron /var/spool/cron/crontabs /etc/crontabs"
    local user_crons_found=0

    for cron_spool in $user_cron_dirs; do
        if [ -d "$cron_spool" ]; then
            log "INFO" "Checking user crontabs in $cron_spool"
            echo "Found: $cron_spool" >> "$REPORT_FILE"

            # Count user cron files
            user_count=0
            for user_cron in "$cron_spool"/*; do
                if [ -e "$user_cron" ] && [ -f "$user_cron" ]; then
                    user_count=$((user_count + 1))
                    user_crons_found=$((user_crons_found + 1))
                    username=$(basename "$user_cron")

                    log "INFO" "  Checking crontab for: $username"
                    echo "  User crontab: $username" >> "$REPORT_FILE"

                    if grep -qE "curl|wget|nc|bash -i|/dev/tcp|base64" "$user_cron" 2>/dev/null; then
                        report "CRITICAL" "CRON" "Suspicious cron job for user: $username"
                        grep -E "curl|wget|nc|bash -i|/dev/tcp|base64" "$user_cron" 2>/dev/null | head -2 >> "$REPORT_FILE"
                    fi
                fi
            done

            if [ $user_count -eq 0 ]; then
                echo "  (no user crontabs)" >> "$REPORT_FILE"
            fi
        else
            log "INFO" "$cron_spool not found"
            echo "Not found: $cron_spool" >> "$REPORT_FILE"
        fi
    done

    # Summary
    echo "" >> "$REPORT_FILE"
    echo "Cron Summary:" >> "$REPORT_FILE"
    echo "  System cron files checked: $cron_files_found" >> "$REPORT_FILE"
    echo "  User crontabs checked: $user_crons_found" >> "$REPORT_FILE"

    if [ $cron_files_found -eq 0 ] && [ $user_crons_found -eq 0 ]; then
        log "WARNING" "No cron files found on this system (unusual)"
        echo "  WARNING: No cron files found (unusual for most systems)" >> "$REPORT_FILE"
    fi
}

# Function to check systemd services and timers
check_systemd() {
    if ! command_exists systemctl; then
        log "INFO" "systemd not available, skipping systemd checks"
        return 0
    fi

    log "INFO" "Checking systemd services and timers..."
    echo "" >> "$REPORT_FILE"
    echo "=== SYSTEMD SERVICES ANALYSIS ===" >> "$REPORT_FILE"

    # Get list of enabled services
    systemctl list-unit-files --type=service --state=enabled 2>/dev/null | grep "\.service" | awk '{print $1}' > /tmp/enabled_services.txt

    # Check if we have a backup to compare
    if [ -f "$BACKUP_DIR/all/latest/system_info/service_status.txt" ]; then
        log "INFO" "Comparing with baseline services"

        # Extract enabled services from backup
        grep "enabled" "$BACKUP_DIR/all/latest/system_info/service_status.txt" 2>/dev/null | awk '{print $1}' > /tmp/backup_services.txt || true

        # Find new enabled services
        comm -13 /tmp/backup_services.txt /tmp/enabled_services.txt > /tmp/new_services.txt

        if [ -s /tmp/new_services.txt ]; then
            while read -r service; do
                report "HIGH" "SYSTEMD" "New enabled service detected: $service"
            done < /tmp/new_services.txt
        fi
    fi

    # Check for suspicious service names
    if grep -E "update|cron|backup|tmp|dev" /tmp/enabled_services.txt 2>/dev/null; then
        log "WARNING" "Services with potentially suspicious names found (manual review needed)"
    fi

    # Check systemd timers (BusyBox-compatible way)
    log "INFO" "Checking systemd timers"
    systemctl list-timers --all 2>/dev/null | grep -v "^NEXT\|^$\|timers listed" | while read -r line; do
        timer_name=$(echo "$line" | awk '{print $NF}')
        if [ -n "$timer_name" ]; then
            # Check if this timer is in our backup
            if [ -f "$BACKUP_DIR/all/latest/system_info/service_status.txt" ]; then
                if ! grep -q "$timer_name" "$BACKUP_DIR/all/latest/system_info/service_status.txt" 2>/dev/null; then
                    report "MEDIUM" "SYSTEMD" "New timer detected: $timer_name"
                fi
            fi
        fi
    done

    # Cleanup temp files
    rm -f /tmp/enabled_services.txt /tmp/backup_services.txt /tmp/new_services.txt 2>/dev/null || true
}

# Function to check rc.local and init scripts
check_init_scripts() {
    log "INFO" "Checking init scripts and rc.local..."
    echo "" >> "$REPORT_FILE"
    echo "=== INIT SCRIPTS ANALYSIS ===" >> "$REPORT_FILE"

    # Check rc.local
    for rc_file in /etc/rc.local /etc/rc.d/rc.local; do
        if [ -f "$rc_file" ]; then
            log "INFO" "Analyzing $rc_file"

            # Check if it's executable
            if [ -x "$rc_file" ]; then
                report "MEDIUM" "INIT" "$rc_file is executable (potential persistence)"

                # Check for suspicious content
                if grep -E "curl|wget|nc|bash -i|/dev/tcp|base64|python -c|perl -e" "$rc_file" 2>/dev/null; then
                    report "CRITICAL" "INIT" "Suspicious commands in $rc_file"
                fi
            fi

            # Compare with backup
            if [ -f "$BACKUP_DIR/all/latest$rc_file" ]; then
                if ! diff -q "$rc_file" "$BACKUP_DIR/all/latest$rc_file" >/dev/null 2>&1; then
                    report "HIGH" "INIT" "$rc_file has been modified since backup"
                fi
            fi
        fi
    done

    # Check init.d scripts
    if [ -d "/etc/init.d" ]; then
        log "INFO" "Checking /etc/init.d scripts"

        # Get list of current init scripts
        if command_exists fd; then
            fd --type f --base-directory /etc/init.d 2>/dev/null | sed 's|^|/etc/init.d/|' | sort > /tmp/current_initd.txt || true
        else
            find /etc/init.d -type f 2>/dev/null | sort > /tmp/current_initd.txt || true
        fi

        # Compare with backup if available
        if [ -d "$BACKUP_DIR/all/latest/etc/init.d" ]; then
            if command_exists fd; then
                fd --type f --base-directory "$BACKUP_DIR/all/latest/etc/init.d" 2>/dev/null | sed "s|^|/etc/init.d/|" | sort > /tmp/backup_initd.txt || true
            else
                find "$BACKUP_DIR/all/latest/etc/init.d" -type f 2>/dev/null | sed "s|$BACKUP_DIR/all/latest||" | sort > /tmp/backup_initd.txt || true
            fi

            # Find new scripts
            comm -13 /tmp/backup_initd.txt /tmp/current_initd.txt > /tmp/new_initd.txt 2>/dev/null || true

            if [ -s /tmp/new_initd.txt ]; then
                while read -r script; do
                    report "HIGH" "INIT" "New init.d script detected: $script"
                done < /tmp/new_initd.txt
            fi
        fi

        # Cleanup
        rm -f /tmp/current_initd.txt /tmp/backup_initd.txt /tmp/new_initd.txt 2>/dev/null || true
    fi
}

# Function to check shell profiles
check_shell_profiles() {
    log "INFO" "Checking shell profile files for backdoors..."
    echo "" >> "$REPORT_FILE"
    echo "=== SHELL PROFILES ANALYSIS ===" >> "$REPORT_FILE"

    # System-wide profiles
    for profile in /etc/profile /etc/bash.bashrc /etc/bashrc /etc/zshrc; do
        if [ -f "$profile" ]; then
            log "INFO" "Analyzing $profile"

            # Check for suspicious patterns
            if grep -E "curl|wget|nc|bash -i|/dev/tcp|base64|eval|exec|python -c|perl -e" "$profile" 2>/dev/null; then
                report "CRITICAL" "PROFILE" "Suspicious commands in $profile"
            fi

            # Compare with backup
            profile_backup="$BACKUP_DIR/all/latest$profile"
            if [ -f "$profile_backup" ]; then
                if ! diff -q "$profile" "$profile_backup" >/dev/null 2>&1; then
                    report "HIGH" "PROFILE" "$profile has been modified since backup"
                fi
            fi
        fi
    done

    # Check profile.d directory
    if [ -d "/etc/profile.d" ]; then
        log "INFO" "Checking /etc/profile.d scripts"

        for script in /etc/profile.d/*.sh; do
            if [ -f "$script" ]; then
                if grep -E "curl|wget|nc|bash -i|/dev/tcp|base64|eval|exec" "$script" 2>/dev/null; then
                    report "CRITICAL" "PROFILE" "Suspicious commands in $script"
                fi
            fi
        done
    fi

    # Check user profiles (only if we can access /home)
    if [ -d "/home" ]; then
        log "INFO" "Checking user profile files"

        for user_home in /home/*; do
            if [ -d "$user_home" ]; then
                username=$(basename "$user_home")

                for profile in .bashrc .bash_profile .profile .zshrc; do
                    user_profile="$user_home/$profile"
                    if [ -f "$user_profile" ]; then
                        if grep -E "curl|wget|nc|bash -i|/dev/tcp|base64|eval|exec" "$user_profile" 2>/dev/null; then
                            report "CRITICAL" "PROFILE" "Suspicious commands in $username's $profile"
                        fi
                    fi
                done
            fi
        done
    fi

    # Check root's profile
    if [ -d "/root" ]; then
        for profile in .bashrc .bash_profile .profile .zshrc; do
            root_profile="/root/$profile"
            if [ -f "$root_profile" ]; then
                if grep -E "curl|wget|nc|bash -i|/dev/tcp|base64|eval|exec" "$root_profile" 2>/dev/null; then
                    report "CRITICAL" "PROFILE" "Suspicious commands in root's $profile"
                fi
            fi
        done
    fi
}

# Function to check LD_PRELOAD and library injection
check_ld_preload() {
    log "INFO" "Checking for LD_PRELOAD and library injection..."
    echo "" >> "$REPORT_FILE"
    echo "=== LD_PRELOAD ANALYSIS ===" >> "$REPORT_FILE"

    # Check /etc/ld.so.preload
    if [ -f "/etc/ld.so.preload" ]; then
        report "HIGH" "LD_PRELOAD" "/etc/ld.so.preload exists (uncommon, potential rootkit)"
        cat /etc/ld.so.preload >> "$REPORT_FILE" 2>/dev/null || true
    fi

    # Check for LD_PRELOAD in environment
    if env | grep -q "LD_PRELOAD" 2>/dev/null; then
        report "HIGH" "LD_PRELOAD" "LD_PRELOAD environment variable is set"
        env | grep "LD_PRELOAD" >> "$REPORT_FILE" 2>/dev/null || true
    fi

    # Check /etc/ld.so.conf and /etc/ld.so.conf.d/
    if [ -f "/etc/ld.so.conf" ]; then
        if [ -f "$BACKUP_DIR/all/latest/etc/ld.so.conf" ]; then
            if ! diff -q /etc/ld.so.conf "$BACKUP_DIR/all/latest/etc/ld.so.conf" >/dev/null 2>&1; then
                report "MEDIUM" "LD_PRELOAD" "/etc/ld.so.conf has been modified"
            fi
        fi
    fi

    if [ -d "/etc/ld.so.conf.d" ]; then
        log "INFO" "Checking /etc/ld.so.conf.d for modifications"

        for conf_file in /etc/ld.so.conf.d/*.conf; do
            if [ -f "$conf_file" ]; then
                backup_file="$BACKUP_DIR/all/latest$conf_file"
                if [ -f "$backup_file" ]; then
                    if ! diff -q "$conf_file" "$backup_file" >/dev/null 2>&1; then
                        report "MEDIUM" "LD_PRELOAD" "$(basename "$conf_file") has been modified"
                    fi
                fi
            fi
        done
    fi
}

# Function to check kernel modules
check_kernel_modules() {
    log "INFO" "Checking kernel modules..."
    echo "" >> "$REPORT_FILE"
    echo "=== KERNEL MODULES ANALYSIS ===" >> "$REPORT_FILE"

    if ! command_exists lsmod; then
        log "INFO" "lsmod not available, skipping kernel module checks"
        return 0
    fi

    # Get current loaded modules
    lsmod | tail -n +2 | awk '{print $1}' | sort > /tmp/current_modules.txt

    # Compare with backup if available
    if [ -f "$BACKUP_DIR/all/latest/system_info/loaded_modules.txt" ]; then
        # Extract module names from backup
        tail -n +2 "$BACKUP_DIR/all/latest/system_info/loaded_modules.txt" 2>/dev/null | awk '{print $1}' | sort > /tmp/backup_modules.txt || true

        # Find new modules
        comm -13 /tmp/backup_modules.txt /tmp/current_modules.txt > /tmp/new_modules.txt 2>/dev/null || true

        if [ -s /tmp/new_modules.txt ]; then
            while read -r module; do
                report "MEDIUM" "KERNEL" "New kernel module loaded: $module"
            done < /tmp/new_modules.txt
        fi
    fi

    # Check for suspicious module names
    if grep -E "rootkit|keylog|hide|stealth" /tmp/current_modules.txt 2>/dev/null; then
        report "CRITICAL" "KERNEL" "Suspicious kernel module names detected"
    fi

    # Cleanup
    rm -f /tmp/current_modules.txt /tmp/backup_modules.txt /tmp/new_modules.txt 2>/dev/null || true
}

# Function to check SSH authorized_keys
check_ssh_keys() {
    log "INFO" "Checking SSH authorized_keys..."
    echo "" >> "$REPORT_FILE"
    echo "=== SSH AUTHORIZED KEYS ANALYSIS ===" >> "$REPORT_FILE"

    # Check root's authorized_keys
    if [ -f "/root/.ssh/authorized_keys" ]; then
        log "INFO" "Analyzing /root/.ssh/authorized_keys"

        # Compare with backup
        if [ -f "$BACKUP_DIR/all/latest/root/.ssh/authorized_keys" ]; then
            if ! diff -q /root/.ssh/authorized_keys "$BACKUP_DIR/all/latest/root/.ssh/authorized_keys" >/dev/null 2>&1; then
                report "CRITICAL" "SSH" "root's authorized_keys has been modified"
                echo "New keys:" >> "$REPORT_FILE"
                diff /root/.ssh/authorized_keys "$BACKUP_DIR/all/latest/root/.ssh/authorized_keys" 2>/dev/null | grep "^<" >> "$REPORT_FILE" || true
            fi
        fi

        # Count keys
        key_count=$(grep -c "^ssh-" /root/.ssh/authorized_keys 2>/dev/null || echo "0")
        if [ "$key_count" -gt 0 ]; then
            log "INFO" "root has $key_count authorized SSH key(s)"
        fi
    fi

    # Check user authorized_keys
    if [ -d "/home" ]; then
        for user_home in /home/*; do
            if [ -d "$user_home/.ssh" ]; then
                username=$(basename "$user_home")
                auth_keys="$user_home/.ssh/authorized_keys"

                if [ -f "$auth_keys" ]; then
                    log "INFO" "Checking $username's authorized_keys"

                    # Compare with backup if available
                    backup_keys="$BACKUP_DIR/all/latest$auth_keys"
                    if [ -f "$backup_keys" ]; then
                        if ! diff -q "$auth_keys" "$backup_keys" >/dev/null 2>&1; then
                            report "HIGH" "SSH" "$username's authorized_keys has been modified"
                        fi
                    fi

                    # Check for suspicious key comments
                    if grep -E "root@|admin@|backdoor|test|temp" "$auth_keys" 2>/dev/null; then
                        report "MEDIUM" "SSH" "Suspicious key comment in $username's authorized_keys"
                    fi
                fi
            fi
        done
    fi
}

# Function to check for unusual SUID/SGID files
check_suid_sgid() {
    log "INFO" "Checking for unusual SUID/SGID files..."
    echo "" >> "$REPORT_FILE"
    echo "=== SUID/SGID FILES ANALYSIS ===" >> "$REPORT_FILE"

    # Find current SUID/SGID files
    log "INFO" "Scanning for SUID/SGID binaries (this may take a while)..."
    if command_exists fd; then
        fd --one-file-system --type f --perm u+s,g+s / --exec ls -l 2>/dev/null | awk '{print $NF}' | sort > /tmp/current_suid.txt || true
    else
        find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -exec ls -l {} \; 2>/dev/null | awk '{print $NF}' | sort > /tmp/current_suid.txt || true
    fi

    # Compare with backup
    if [ -f "$BACKUP_DIR/all/latest/system_info/suid_sgid_files.txt" ]; then
        # Extract file paths from backup
        awk '{print $NF}' "$BACKUP_DIR/all/latest/system_info/suid_sgid_files.txt" 2>/dev/null | sort > /tmp/backup_suid.txt || true

        # Find new SUID/SGID files
        comm -13 /tmp/backup_suid.txt /tmp/current_suid.txt > /tmp/new_suid.txt 2>/dev/null || true

        if [ -s /tmp/new_suid.txt ]; then
            while read -r file; do
                report "CRITICAL" "SUID" "New SUID/SGID file detected: $file"
            done < /tmp/new_suid.txt
        fi
    fi

    # Check for SUID files in unusual locations
    if grep -E "/tmp/|/var/tmp/|/dev/shm/" /tmp/current_suid.txt 2>/dev/null; then
        report "CRITICAL" "SUID" "SUID/SGID files in temporary directories (likely malicious)"
    fi

    # Cleanup
    rm -f /tmp/current_suid.txt /tmp/backup_suid.txt /tmp/new_suid.txt 2>/dev/null || true
}

# Display help
show_help() {
    cat << EOF
Persistence Detection Tool - CCDC Edition

Usage: $0 [OPTIONS]

Options:
  -h, --help              Show this help message
  -v, --verbose           Enable verbose output
  -a, --all               Run all checks (default)
  -c, --cron              Check cron jobs only
  -s, --systemd           Check systemd services only
  -i, --init              Check init scripts only
  -p, --profiles          Check shell profiles only
  -l, --ld-preload        Check LD_PRELOAD only
  -k, --kernel            Check kernel modules only
  --ssh                   Check SSH keys only
  --suid                  Check SUID/SGID files only

Environment Variables:
  KK_BASE_DIR             Base directory (default: /opt/keyboard_kowboys)
  KK_LOG_DIR              Log directory (default: \$KK_BASE_DIR/logs)
  KK_BACKUP_DIR           Backup directory (default: \$KK_BASE_DIR/backups)

Examples:
  $0 -v                   Run all checks with verbose output
  $0 --cron --systemd     Check only cron and systemd
  $0 --ssh --profiles     Check SSH keys and shell profiles

EOF
    exit 0
}

# Parse command line arguments
RUN_ALL=true
RUN_CRON=false
RUN_SYSTEMD=false
RUN_INIT=false
RUN_PROFILES=false
RUN_LD_PRELOAD=false
RUN_KERNEL=false
RUN_SSH=false
RUN_SUID=false

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -a|--all)
            RUN_ALL=true
            shift
            ;;
        -c|--cron)
            RUN_ALL=false
            RUN_CRON=true
            shift
            ;;
        -s|--systemd)
            RUN_ALL=false
            RUN_SYSTEMD=true
            shift
            ;;
        -i|--init)
            RUN_ALL=false
            RUN_INIT=true
            shift
            ;;
        -p|--profiles)
            RUN_ALL=false
            RUN_PROFILES=true
            shift
            ;;
        -l|--ld-preload)
            RUN_ALL=false
            RUN_LD_PRELOAD=true
            shift
            ;;
        -k|--kernel)
            RUN_ALL=false
            RUN_KERNEL=true
            shift
            ;;
        --ssh)
            RUN_ALL=false
            RUN_SSH=true
            shift
            ;;
        --suid)
            RUN_ALL=false
            RUN_SUID=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Main execution
log "INFO" "Starting persistence detection scan"
log "INFO" "Report will be saved to: $REPORT_FILE"

echo "=== PERSISTENCE DETECTION REPORT ===" > "$REPORT_FILE"
echo "Generated: $(date)" >> "$REPORT_FILE"
echo "System: $(hostname)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Run checks based on options
if [ "$RUN_ALL" = true ] || [ "$RUN_CRON" = true ]; then
    check_cron
fi

if [ "$RUN_ALL" = true ] || [ "$RUN_SYSTEMD" = true ]; then
    check_systemd
fi

if [ "$RUN_ALL" = true ] || [ "$RUN_INIT" = true ]; then
    check_init_scripts
fi

if [ "$RUN_ALL" = true ] || [ "$RUN_PROFILES" = true ]; then
    check_shell_profiles
fi

if [ "$RUN_ALL" = true ] || [ "$RUN_LD_PRELOAD" = true ]; then
    check_ld_preload
fi

if [ "$RUN_ALL" = true ] || [ "$RUN_KERNEL" = true ]; then
    check_kernel_modules
fi

if [ "$RUN_ALL" = true ] || [ "$RUN_SSH" = true ]; then
    check_ssh_keys
fi

if [ "$RUN_ALL" = true ] || [ "$RUN_SUID" = true ]; then
    check_suid_sgid
fi

# Summary
echo "" >> "$REPORT_FILE"
echo "=== SUMMARY ===" >> "$REPORT_FILE"
echo "Total issues found: $ISSUES_FOUND" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

log "INFO" "Persistence detection scan completed"
log "INFO" "Total issues found: $ISSUES_FOUND"
echo ""
echo "=== SCAN COMPLETE ==="
echo "Issues found: $ISSUES_FOUND"
echo "Report saved to: $REPORT_FILE"
echo ""

if [ "$ISSUES_FOUND" -gt 0 ]; then
    echo "WARNING: Potential persistence mechanisms detected!"
    echo "Review the report for details: $REPORT_FILE"
    exit 1
else
    echo "No obvious persistence mechanisms detected."
    echo "This does not guarantee the system is clean - manual review recommended."
    exit 0
fi
