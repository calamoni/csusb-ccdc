#!/bin/sh
# Enhanced monitoring dashboard - POSIX compliant
# Shows comprehensive monitoring status and recent alerts

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get system info
get_system_info() {
    echo "=== SYSTEM INFORMATION ==="
    echo "Hostname: $(hostname 2>/dev/null || echo 'Unknown')"
    echo "Uptime: $(uptime 2>/dev/null | awk '{print $3,$4}' | sed 's/,//' || echo 'Unknown')"
    echo "Load: $(uptime 2>/dev/null | awk -F'load average:' '{print $2}' || echo 'Unknown')"
    echo "Users: $(who | wc -l 2>/dev/null || echo '0')"
    echo ""
}

# Function to get monitoring status
get_monitoring_status() {
    echo "=== MONITORING STATUS ==="
    
    # File monitoring status
    if pgrep -f monitor.sh >/dev/null 2>&1; then
        local pid=$(pgrep -f monitor.sh)
        local start_time=$(ps -o lstart= -p "$pid" 2>/dev/null || echo 'Unknown')
        echo "🔴 FILE MONITORING: ACTIVE (PID: $pid)"
        echo "   Started: $start_time"
        
        # Count recent alerts
        if [ -f "${LOG_DIR:-/tmp}/monitor.log" ]; then
            local alert_count=$(grep -c "ALERT\|WARNING\|CRITICAL" "${LOG_DIR:-/tmp}/monitor.log" 2>/dev/null || echo "0")
            echo "   Recent alerts: $alert_count"
        fi
    else
        echo "⚪ FILE MONITORING: INACTIVE"
    fi
    
    # Performance monitoring status
    if pgrep -f run_monitoring.sh >/dev/null 2>&1; then
        local pid=$(pgrep -f run_monitoring.sh)
        local start_time=$(ps -o lstart= -p "$pid" 2>/dev/null || echo 'Unknown')
        echo "🔴 PERFORMANCE MONITORING: ACTIVE (PID: $pid)"
        echo "   Started: $start_time"
        
        # Count data files
        if [ -d "${LOG_DIR:-/tmp}/monitoring/data" ]; then
            local data_count=$(ls "${LOG_DIR:-/tmp}/monitoring/data" 2>/dev/null | wc -l)
            echo "   Data points: $data_count"
        fi
    else
        echo "⚪ PERFORMANCE MONITORING: INACTIVE"
    fi
    echo ""
}

# Function to get system health
get_system_health() {
    echo "=== SYSTEM HEALTH ==="
    
    # CPU usage
    if command_exists top; then
        local cpu_usage=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "Unknown")
        echo "CPU Usage: ${cpu_usage}%"
    fi
    
    # Memory usage
    if command_exists free; then
        local mem_usage=$(free 2>/dev/null | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}' 2>/dev/null || echo "Unknown")
        echo "Memory: $mem_usage"
    fi
    
    # Disk usage
    if command_exists df; then
        local disk_usage=$(df -h / 2>/dev/null | awk 'NR==2{print $5}' 2>/dev/null || echo "Unknown")
        echo "Disk: $disk_usage"
    fi
    
    # Network connections
    if command_exists ss; then
        local conn_count=$(ss -tuln 2>/dev/null | wc -l 2>/dev/null || echo "Unknown")
        echo "Network connections: $conn_count"
    elif command_exists netstat; then
        local conn_count=$(netstat -tuln 2>/dev/null | wc -l 2>/dev/null || echo "Unknown")
        echo "Network connections: $conn_count"
    fi
    echo ""
}

# Function to show recent alerts
get_recent_alerts() {
    echo "=== RECENT ALERTS ==="
    
    if [ -f "${LOG_DIR:-/tmp}/monitor.log" ]; then
        # Show last 10 alerts
        grep -E "(ALERT|WARNING|CRITICAL)" "${LOG_DIR:-/tmp}/monitor.log" 2>/dev/null | tail -10 | while read line; do
            echo "$line"
        done
    else
        echo "No monitoring log found"
    fi
    echo ""
}

# Function to show critical file status
get_critical_files() {
    echo "=== CRITICAL FILES STATUS ==="
    
    local critical_files="/etc/passwd /etc/shadow /etc/sudoers /etc/crontab"
    
    for file in $critical_files; do
        if [ -f "$file" ]; then
            local perms=$(ls -l "$file" 2>/dev/null | awk '{print $1}' || echo "Unknown")
            local owner=$(ls -l "$file" 2>/dev/null | awk '{print $3}' || echo "Unknown")
            local modified=$(ls -l "$file" 2>/dev/null | awk '{print $6, $7, $8}' || echo "Unknown")
            echo "✓ $file: $perms $owner (modified: $modified)"
        else
            echo "✗ $file: NOT FOUND"
        fi
    done
    echo ""
}


# Main dashboard function
show_dashboard() {
    clear
    echo "==============================================="
    echo "    KEYBOARD KOWBOYS MONITORING DASHBOARD"
    echo "==============================================="
    echo "Last updated: $(date)"
    echo ""
    
    get_system_info
    get_monitoring_status
    get_system_health
    get_critical_files
    get_recent_alerts
    
    echo "==============================================="
    echo "Commands: just monitor-status, just start-monitor, just stop-monitor"
    echo "==============================================="
}

# Check if running in watch mode
if [ "$1" = "--watch" ]; then
    interval="${2:-5}"

    # Ensure minimum interval of 3 seconds for readability
    if [ "$interval" -lt 3 ]; then
        interval=3
    fi

    echo "Starting continuous monitoring (interval: ${interval}s)"
    echo "Press Ctrl+C to stop"
    echo ""

    while true; do
        show_dashboard
        sleep "$interval"
    done
else
    show_dashboard
fi