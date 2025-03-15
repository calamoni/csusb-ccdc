#!/bin/sh
# Script to analyze system logs for suspicious activity
# Usage: log_analyzer.sh [hours]

set -e

# Default to 1 hour if no argument is provided
if [ $# -ge 1 ]; then
    HOURS="$1"
else
    HOURS="1"
fi

echo "=== Log Analysis - Last $HOURS Hour(s) ==="
echo "Started at $(date)"
echo ""

# Calculate the timestamp for X hours ago
HOURS_AGO=$(date -d "$HOURS hours ago" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -v-"${HOURS}H" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
if [ -z "$HOURS_AGO" ]; then
    # Fallback method if date commands fail
    SECONDS_AGO=$((HOURS * 3600))
    HOURS_AGO=$(date -d "@$(($(date +%s) - SECONDS_AGO))" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "$(($(date +%s) - SECONDS_AGO))" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
    
    if [ -z "$HOURS_AGO" ]; then
        echo "Warning: Could not calculate timestamp for $HOURS hours ago. Using all available logs."
        HOURS_AGO=""
    fi
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to filter logs by time if possible
filter_by_time() {
    if [ -n "$HOURS_AGO" ]; then
        grep -a "$HOURS_AGO\|$(date +%Y-%m-%d)" 2>/dev/null || cat
    else
        cat
    fi
}

# Analysis: Authentication logs
echo "=== Authentication Logs Analysis ==="
if [ -f "/var/log/auth.log" ]; then
    echo "Failed login attempts:"
    grep -a "Failed password\|authentication failure\|Invalid user" /var/log/auth.log | filter_by_time | sort | uniq -c | sort -nr
    
    echo "Successful logins:"
    grep -a "Accepted password\|session opened" /var/log/auth.log | filter_by_time | sort | uniq -c | sort -nr
    
    echo "Root login attempts:"
    grep -a "ROOT LOGIN\|root" /var/log/auth.log | filter_by_time | sort | uniq -c | sort -nr
elif [ -f "/var/log/secure" ]; then
    echo "Failed login attempts:"
    grep -a "Failed password\|authentication failure\|Invalid user" /var/log/secure | filter_by_time | sort | uniq -c | sort -nr
    
    echo "Successful logins:"
    grep -a "Accepted password\|session opened" /var/log/secure | filter_by_time | sort | uniq -c | sort -nr
    
    echo "Root login attempts:"
    grep -a "ROOT LOGIN\|root" /var/log/secure | filter_by_time | sort | uniq -c | sort -nr
else
    echo "No authentication logs found at /var/log/auth.log or /var/log/secure"
fi
echo ""

# Analysis: Sudo usage
echo "=== Sudo Usage Analysis ==="
if [ -f "/var/log/auth.log" ]; then
    grep -a "sudo:" /var/log/auth.log | filter_by_time | sort | uniq -c | sort -nr
elif [ -f "/var/log/secure" ]; then
    grep -a "sudo:" /var/log/secure | filter_by_time | sort | uniq -c | sort -nr
else
    echo "No sudo logs found at /var/log/auth.log or /var/log/secure"
fi
echo ""

# Analysis: System logs
echo "=== System Logs Analysis ==="
if [ -f "/var/log/syslog" ]; then
    LOG_FILE="/var/log/syslog"
elif [ -f "/var/log/messages" ]; then
    LOG_FILE="/var/log/messages"
else
    LOG_FILE=""
    echo "No system logs found at /var/log/syslog or /var/log/messages"
fi

if [ -n "$LOG_FILE" ]; then
    echo "Critical errors and warnings:"
    grep -a -i "error\|critical\|warning\|fail" "$LOG_FILE" | filter_by_time | grep -v "does not exist\|not found" | sort | uniq -c | sort -nr | head -20
    echo "(showing top 20 entries only)"
    
    echo "Service restarts:"
    grep -a "restart\|starting\|started\|stopping\|stopped" "$LOG_FILE" | filter_by_time | sort | uniq -c | sort -nr | head -20
    echo "(showing top 20 entries only)"
fi
echo ""

# Analysis: Journal logs (if available)
if command_exists journalctl; then
    echo "=== Journalctl Analysis ==="
    
    echo "System errors (last $HOURS hour(s)):"
    if [ -n "$HOURS_AGO" ]; then
        journalctl -p err..emerg --since "$HOURS_AGO" | grep -v "does not exist\|not found" | sort | uniq -c | sort -nr | head -20
    else
        journalctl -p err..emerg --since "$(date +%Y-%m-%d)" | grep -v "does not exist\|not found" | sort | uniq -c | sort -nr | head -20
    fi
    echo "(showing top 20 entries only)"
    
    echo "Authentication events (last $HOURS hour(s)):"
    if [ -n "$HOURS_AGO" ]; then
        journalctl _COMM=sshd --since "$HOURS_AGO" | sort | uniq -c | sort -nr | head -20
    else
        journalctl _COMM=sshd --since "$(date +%Y-%m-%d)" | sort | uniq -c | sort -nr | head -20
    fi
    echo "(showing top 20 entries only)"
fi
echo ""

# Analysis: HTTP server logs (if available)
echo "=== Web Server Log Analysis ==="
HTTP_LOGS="/var/log/apache2/access.log /var/log/httpd/access_log /var/log/nginx/access.log"
for log in $HTTP_LOGS; do
    if [ -f "$log" ]; then
        echo "Analyzing $log:"
        
        echo "Top client IPs:"
        cat "$log" | filter_by_time | awk '{print $1}' | sort | uniq -c | sort -nr | head -10
        
        echo "HTTP error responses (4xx, 5xx):"
        grep -a " 4[0-9][0-9] \| 5[0-9][0-9] " "$log" | filter_by_time | sort | uniq -c | sort -nr | head -10
        
        echo "Unusual HTTP requests (potential attacks):"
        grep -a -i "SELECT \|UNION \|.php \|cmd \|config \|admin \|.aspx " "$log" | filter_by_time | sort | uniq -c | sort -nr | head -10
    fi
done

if [ ! -f "/var/log/apache2/access.log" ] && [ ! -f "/var/log/httpd/access_log" ] && [ ! -f "/var/log/nginx/access.log" ]; then
    echo "No web server logs found"
fi
echo ""

# Analysis: Failed processes
echo "=== Failed Process Analysis ==="
if command_exists systemctl; then
    echo "Failed systemd services:"
    systemctl --failed
    
    echo "Recent service failures (last $HOURS hour(s)):"
    if [ -n "$HOURS_AGO" ]; then
        journalctl -p err..emerg --since "$HOURS_AGO" _SYSTEMD_UNIT | sort | uniq -c | sort -nr | head -10
    else
        journalctl -p err..emerg --since "$(date +%Y-%m-%d)" _SYSTEMD_UNIT | sort | uniq -c | sort -nr | head -10
    fi
fi
echo ""

# Analysis: Cron jobs
echo "=== Cron Job Analysis ==="
if [ -f "/var/log/cron" ]; then
    grep -a -v "pam_unix\|session\|CMD" /var/log/cron | filter_by_time | sort | uniq -c | sort -nr | head -20
    echo "(showing top 20 entries only)"
elif [ -f "/var/log/syslog" ]; then
    grep -a "CRON" /var/log/syslog | filter_by_time | sort | uniq -c | sort -nr | head -20
    echo "(showing top 20 entries only)"
else
    echo "No cron logs found"
fi
echo ""

# Analysis: Kernel logs (dmesg)
echo "=== Kernel Log Analysis ==="
if command_exists dmesg; then
    echo "Recent kernel errors and warnings:"
    dmesg | grep -a -i "error\|warn\|fail" | tail -20
    echo "(showing last 20 entries only)"
else
    echo "dmesg command not available"
fi
echo ""

# Generate log summary
echo "=== Log Analysis Summary ==="
echo "Period analyzed: Last $HOURS hour(s)"

# Count authentication failures
AUTH_FAILURES=0
if [ -f "/var/log/auth.log" ]; then
    AUTH_FAILURES=$(grep -a "Failed password\|authentication failure" /var/log/auth.log | filter_by_time | wc -l)
elif [ -f "/var/log/secure" ]; then
    AUTH_FAILURES=$(grep -a "Failed password\|authentication failure" /var/log/secure | filter_by_time | wc -l)
fi
echo "Authentication failures: $AUTH_FAILURES"

# Count sudo commands
SUDO_COMMANDS=0
if [ -f "/var/log/auth.log" ]; then
    SUDO_COMMANDS=$(grep -a "sudo:" /var/log/auth.log | filter_by_time | wc -l)
elif [ -f "/var/log/secure" ]; then
    SUDO_COMMANDS=$(grep -a "sudo:" /var/log/secure | filter_by_time | wc -l)
fi
echo "Sudo commands executed: $SUDO_COMMANDS"

# Count system errors
SYS_ERRORS=0
if [ -n "$LOG_FILE" ]; then
    SYS_ERRORS=$(grep -a -i "error\|critical\|fail" "$LOG_FILE" | filter_by_time | wc -l)
fi
echo "System errors/failures: $SYS_ERRORS"

echo ""
echo "=== Log Analysis Complete ==="
echo "Completed at $(date)"
exit 0
