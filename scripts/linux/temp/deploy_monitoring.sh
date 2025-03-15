#!/bin/sh
# Script to deploy system monitoring tools and configurations
# This script sets up basic system monitoring

set -e

BASE_DIR="/opt/keyboard_kowboys"
CONFIG_DIR="$BASE_DIR/configs"
LOG_DIR="$BASE_DIR/logs"

echo "=== Deploying System Monitoring ==="
echo "Starting at $(date)"

# Create monitoring directories
mkdir -p "$LOG_DIR/monitoring"
mkdir -p "$CONFIG_DIR/monitoring"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to deploy a monitoring tool
deploy_tool() {
    tool="$1"
    package="$2"
    config_source="$3"
    config_dest="$4"
    
    echo "Checking for $tool..."
    if ! command_exists "$tool"; then
        echo "$tool not found. Attempting to install $package..."
        # Try different package managers
        if command_exists apt-get; then
            apt-get update && apt-get install -y "$package"
        elif command_exists yum; then
            yum install -y "$package"
        elif command_exists dnf; then
            dnf install -y "$package"
        elif command_exists zypper; then
            zypper install -y "$package"
        else
            echo "Error: No supported package manager found. Please install $package manually."
            return 1
        fi
    fi
    
    # Check if install succeeded
    if ! command_exists "$tool"; then
        echo "Error: Failed to install $tool"
        return 1
    fi
    
    # If config provided and exists, deploy it
    if [ -n "$config_source" ] && [ -n "$config_dest" ] && [ -f "$config_source" ]; then
        echo "Deploying configuration for $tool..."
        cp "$config_source" "$config_dest"
        echo "Configuration deployed to $config_dest"
    fi
    
    echo "$tool successfully deployed"
    return 0
}

# Deploy basic system monitoring tools
echo "=== Deploying Basic System Monitoring ==="

# Set up sysstat if available
if deploy_tool "sar" "sysstat" "$CONFIG_DIR/monitoring/sysstat.conf" "/etc/sysstat/sysstat.conf"; then
    # Enable and start sysstat service if systemd is available
    if command_exists systemctl; then
        systemctl enable sysstat
        systemctl start sysstat
    else
        # Try legacy service management
        if [ -f "/etc/init.d/sysstat" ]; then
            /etc/init.d/sysstat start
        fi
    fi
    
    # Set up a basic cronjob for sysstat if it doesn't exist
    if [ ! -f "/etc/cron.d/sysstat" ]; then
        echo "*/10 * * * * root /usr/lib/sysstat/sa1 1 1" > /etc/cron.d/sysstat
        echo "53 23 * * * root /usr/lib/sysstat/sa2 -A" >> /etc/cron.d/sysstat
    fi
    
    echo "sysstat setup completed"
else
    echo "Warning: sysstat setup failed or was skipped"
fi

# Set up Logwatch for log monitoring
if deploy_tool "logwatch" "logwatch" "$CONFIG_DIR/monitoring/logwatch.conf" "/etc/logwatch/conf/logwatch.conf"; then
    echo "Setting up daily logwatch report..."
    # Create a simple cron job for logwatch if it doesn't exist
    if [ ! -f "/etc/cron.daily/logwatch" ]; then
        echo "#!/bin/sh" > /etc/cron.daily/logwatch
        echo "/usr/sbin/logwatch --output mail --mailto root --detail high" >> /etc/cron.daily/logwatch
        chmod +x /etc/cron.daily/logwatch
    fi
    echo "Logwatch setup completed"
else
    echo "Warning: Logwatch setup failed or was skipped"
fi

# Set up custom monitoring scripts
echo "=== Setting up Custom Monitoring ==="

# Create CPU monitoring script
cat > "$LOG_DIR/monitoring/cpu_monitor.sh" << 'EOF'
#!/bin/sh
OUTFILE="$1/cpu_$(date +%Y%m%d).log"
echo "=== CPU Stats $(date) ===" >> "$OUTFILE"
top -b -n 1 | head -20 >> "$OUTFILE"
echo "CPU usage by process:" >> "$OUTFILE"
ps -eo pid,ppid,%cpu,%mem,cmd --sort=-%cpu | head -15 >> "$OUTFILE"
echo "" >> "$OUTFILE"
EOF
chmod +x "$LOG_DIR/monitoring/cpu_monitor.sh"

# Create memory monitoring script
cat > "$LOG_DIR/monitoring/memory_monitor.sh" << 'EOF'
#!/bin/sh
OUTFILE="$1/memory_$(date +%Y%m%d).log"
echo "=== Memory Stats $(date) ===" >> "$OUTFILE"
free -m >> "$OUTFILE"
echo "Memory usage by process:" >> "$OUTFILE"
ps -eo pid,ppid,%cpu,%mem,cmd --sort=-%mem | head -15 >> "$OUTFILE"
echo "" >> "$OUTFILE"
EOF
chmod +x "$LOG_DIR/monitoring/memory_monitor.sh"

# Create disk monitoring script
cat > "$LOG_DIR/monitoring/disk_monitor.sh" << 'EOF'
#!/bin/sh
OUTFILE="$1/disk_$(date +%Y%m%d).log"
echo "=== Disk Stats $(date) ===" >> "$OUTFILE"
df -h >> "$OUTFILE"
echo "Disk I/O:" >> "$OUTFILE"
if command -v iostat >/dev/null 2>&1; then
    iostat -x >> "$OUTFILE"
else
    echo "iostat not available" >> "$OUTFILE"
fi
echo "" >> "$OUTFILE"
EOF
chmod +x "$LOG_DIR/monitoring/disk_monitor.sh"

# Create network monitoring script
cat > "$LOG_DIR/monitoring/network_monitor.sh" << 'EOF'
#!/bin/sh
OUTFILE="$1/network_$(date +%Y%m%d).log"
echo "=== Network Stats $(date) ===" >> "$OUTFILE"
if command -v ss >/dev/null 2>&1; then
    echo "Active connections:" >> "$OUTFILE"
    ss -tuln >> "$OUTFILE"
elif command -v netstat >/dev/null 2>&1; then
    echo "Active connections:" >> "$OUTFILE"
    netstat -tuln >> "$OUTFILE"
else
    echo "No network monitoring tools available" >> "$OUTFILE"
fi
echo "" >> "$OUTFILE"
EOF
chmod +x "$LOG_DIR/monitoring/network_monitor.sh"

# Create master monitoring script
cat > "$BASE_DIR/scripts/run_monitoring.sh" << EOF
#!/bin/sh
# Master script to run all monitoring scripts

LOG_DIR="$LOG_DIR/monitoring/data"
mkdir -p "\$LOG_DIR"

# Run all monitoring scripts
"$LOG_DIR/monitoring/cpu_monitor.sh" "\$LOG_DIR"
"$LOG_DIR/monitoring/memory_monitor.sh" "\$LOG_DIR"
"$LOG_DIR/monitoring/disk_monitor.sh" "\$LOG_DIR"
"$LOG_DIR/monitoring/network_monitor.sh" "\$LOG_DIR"

# Cleanup old logs (keep 7 days)
find "\$LOG_DIR" -name "*.log" -type f -mtime +7 -delete

echo "Monitoring completed at \$(date)"
EOF
chmod +x "$BASE_DIR/scripts/run_monitoring.sh"

# Create a crontab entry for regular monitoring
if [ -d "/etc/cron.d" ]; then
    echo "Setting up cron job for monitoring..."
    cat > "/etc/cron.d/kb_kowboys_monitoring" << EOF
# Run system monitoring every hour
0 * * * * root $BASE_DIR/scripts/run_monitoring.sh > /dev/null 2>&1
EOF
    echo "Cron job created"
else
    echo "Warning: /etc/cron.d directory not found. Please set up monitoring cron job manually."
fi

# Run initial monitoring
echo "Running initial monitoring check..."
"$BASE_DIR/scripts/run_monitoring.sh"

echo "=== Monitoring Deployment Complete ==="
echo "Completed at $(date)"
exit 0
