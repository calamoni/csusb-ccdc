#!/bin/sh
# Default to 1 hour if no argument is provided
if [ $# -ge 1 ]; then
    HOURS="$1"
else
    HOURS="1"
fi

echo "=== Log Analysis - Last $HOURS Hour(s) ==="
echo "Started at $(date)"
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# BusyBox-compatible function to get today's date in YYYY-MM-DD format
get_today() {
    date "+%Y-%m-%d" 2>/dev/null || date "+%Y-%m-%d" 2>/dev/null
}

TODAY=$(get_today)

# Function to filter logs by time if possible
# This simplified version just filters for today's date
filter_by_time() {
    if [ -n "$TODAY" ]; then
        grep "$TODAY" 2>/dev/null || cat
    else
        cat
    fi
}

echo "Note: On BusyBox systems, time filtering is limited to today's date ($TODAY)"
echo ""

# Analysis: Authentication logs
echo "=== Authentication Logs Analysis ==="
AUTH_FOUND=0

for auth_log in "/var/log/auth.log" "/var/log/secure"; do
    if [ -f "$auth_log" ]; then
        AUTH_FOUND=1
        echo "Analyzing $auth_log:"
        
        echo "Failed login attempts:"
        grep "Failed password\|authentication failure\|Invalid user" "$auth_log" 2>/dev/null | filter_by_time | sort | uniq -c | sort -rn 2>/dev/null || echo "None found or command failed"
        
        echo "Successful logins:"
        grep "Accepted password\|session opened" "$auth_log" 2>/dev/null | filter_by_time | sort | uniq -c | sort -rn 2>/dev/null || echo "None found or command failed"
        
        echo "Root login attempts:"
        grep "ROOT LOGIN\|root" "$auth_log" 2>/dev/null | filter_by_time | sort | uniq -c | sort -rn 2>/dev/null || echo "None found or command failed"
    fi
done

if [ "$AUTH_FOUND" -eq 0 ]; then
    echo "No authentication logs found at /var/log/auth.log or /var/log/secure"
fi
echo ""

# Analysis: Sudo usage
echo "=== Sudo Usage Analysis ==="
SUDO_FOUND=0

for auth_log in "/var/log/auth.log" "/var/log/secure"; do
    if [ -f "$auth_log" ]; then
        SUDO_FOUND=1
        grep "sudo:" "$auth_log" 2>/dev/null | filter_by_time | sort | uniq -c | sort -rn 2>/dev/null || echo "No sudo entries found in $auth_log"
    fi
done

if [ "$SUDO_FOUND" -eq 0 ]; then
    echo "No sudo logs found at /var/log/auth.log or /var/log/secure"
fi
echo ""

# Analysis: System logs
echo "=== System Logs Analysis ==="
LOG_FILE=""

for syslog in "/var/log/syslog" "/var/log/messages"; do
    if [ -f "$syslog" ]; then
        LOG_FILE="$syslog"
        break
    fi
done

if [ -n "$LOG_FILE" ]; then
    echo "Analyzing $LOG_FILE:"
    
    echo "Critical errors and warnings:"
    grep -i "error\|critical\|warning\|fail" "$LOG_FILE" 2>/dev/null | filter_by_time | grep -v "does not exist\|not found" 2>/dev/null | sort | uniq -c | sort -rn 2>/dev/null | head -20 || echo "None found or command failed"
    echo "(showing top 20 entries only)"
    
    echo "Service restarts:"
    grep "restart\|starting\|started\|stopping\|stopped" "$LOG_FILE" 2>/dev/null | filter_by_time | sort | uniq -c | sort -rn 2>/dev/null | head -20 || echo "None found or command failed"
    echo "(showing top 20 entries only)"
else
    echo "No system logs found at /var/log/syslog or /var/log/messages"
fi
echo ""

# Analysis: Journal logs (if available)
if command_exists journalctl; then
    echo "=== Journalctl Analysis ==="
    
    echo "System errors (today):"
    journalctl -p err..emerg --since "$TODAY" 2>/dev/null | grep -v "does not exist\|not found" 2>/dev/null | sort | uniq -c | sort -rn 2>/dev/null | head -20 || echo "No entries found or command failed"
    echo "(showing top 20 entries only)"
    
    echo "Authentication events (today):"
    journalctl _COMM=sshd --since "$TODAY" 2>/dev/null | sort | uniq -c | sort -rn 2>/dev/null | head -20 || echo "No entries found or command failed"
    echo "(showing top 20 entries only)"
else
    echo "=== Journalctl Analysis ==="
    echo "journalctl command not available"
fi
echo ""

# Analysis: HTTP server logs (if available)
echo "=== Web Server Log Analysis ==="
HTTP_FOUND=0

for log in "/var/log/apache2/access.log" "/var/log/httpd/access_log" "/var/log/nginx/access.log"; do
    if [ -f "$log" ]; then
        HTTP_FOUND=1
        echo "Analyzing $log:"
        
        echo "Top client IPs:"
        cat "$log" 2>/dev/null | filter_by_time | awk '{print $1}' 2>/dev/null | sort | uniq -c | sort -rn 2>/dev/null | head -10 || echo "Could not process log file"
        
        echo "HTTP error responses (4xx, 5xx):"
        grep " 4[0-9][0-9] \| 5[0-9][0-9] " "$log" 2>/dev/null | filter_by_time | sort | uniq -c | sort -rn 2>/dev/null | head -10 || echo "No errors found or command failed"
        
        echo "Unusual HTTP requests (potential attacks):"
        grep -i "SELECT \|UNION \|.php \|cmd \|config \|admin \|.aspx " "$log" 2>/dev/null | filter_by_time | sort | uniq -c | sort -rn 2>/dev/null | head -10 || echo "None found or command failed"
    fi
done

if [ "$HTTP_FOUND" -eq 0 ]; then
    echo "No web server logs found"
fi
echo ""

# Analysis: Failed processes
echo "=== Failed Process Analysis ==="
if command_exists systemctl; then
    echo "Failed systemd services:"
    systemctl --failed 2>/dev/null || echo "Could not check failed services"
    
    if command_exists journalctl; then
        echo "Recent service failures (today):"
        journalctl -p err..emerg --since "$TODAY" _SYSTEMD_UNIT 2>/dev/null | sort | uniq -c | sort -rn 2>/dev/null | head -10 || echo "None found or command failed"
    fi
else
    echo "systemctl command not available"
fi
echo ""

# Analysis: Cron jobs
echo "=== Cron Job Analysis ==="
CRON_FOUND=0

if [ -f "/var/log/cron" ]; then
    CRON_FOUND=1
    grep -v "pam_unix\|session\|CMD" "/var/log/cron" 2>/dev/null | filter_by_time | sort | uniq -c | sort -rn 2>/dev/null | head -20 || echo "Could not process cron log"
    echo "(showing top 20 entries only)"
elif [ -f "/var/log/syslog" ]; then
    CRON_FOUND=1
    grep "CRON" "/var/log/syslog" 2>/dev/null | filter_by_time | sort | uniq -c | sort -rn 2>/dev/null | head -20 || echo "Could not process syslog for cron entries"
    echo "(showing top 20 entries only)"
fi

if [ "$CRON_FOUND" -eq 0 ]; then
    echo "No cron logs found"
fi
echo ""

# Analysis: Kernel logs (dmesg)
echo "=== Kernel Log Analysis ==="
if command_exists dmesg; then
    echo "Recent kernel errors and warnings:"
    dmesg 2>/dev/null | grep -i "error\|warn\|fail" 2>/dev/null | tail -20 || echo "Could not process dmesg output"
    echo "(showing last 20 entries only)"
else
    echo "dmesg command not available"
fi
echo ""

# Generate log summary
echo "=== Log Analysis Summary ==="
echo "Period analyzed: Today ($TODAY)"

# Count authentication failures
AUTH_FAILURES=0
for auth_log in "/var/log/auth.log" "/var/log/secure"; do
    if [ -f "$auth_log" ]; then
        COUNT=$(grep "Failed password\|authentication failure" "$auth_log" 2>/dev/null | filter_by_time | wc -l 2>/dev/null || echo 0)
        AUTH_FAILURES=$((AUTH_FAILURES + COUNT))
    fi
done
echo "Authentication failures: $AUTH_FAILURES"

# Count sudo commands
SUDO_COMMANDS=0
for auth_log in "/var/log/auth.log" "/var/log/secure"; do
    if [ -f "$auth_log" ]; then
        COUNT=$(grep "sudo:" "$auth_log" 2>/dev/null | filter_by_time | wc -l 2>/dev/null || echo 0)
        SUDO_COMMANDS=$((SUDO_COMMANDS + COUNT))
    fi
done
echo "Sudo commands executed: $SUDO_COMMANDS"

# Count system errors
SYS_ERRORS=0
if [ -n "$LOG_FILE" ]; then
    SYS_ERRORS=$(grep -i "error\|critical\|fail" "$LOG_FILE" 2>/dev/null | filter_by_time | wc -l 2>/dev/null || echo 0)
fi
echo "System errors/failures: $SYS_ERRORS"

echo ""
echo "=== Log Analysis Complete ==="
echo "Completed at $(date)"
exit 0
