#!/bin/sh
# Script to perform deep scanning of network connections
# Provides more detailed information than basic ss command

set -e

echo "=== Deep Connection Scan ==="
echo "Scan time: $(date)"
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for established connections
echo "=== Established Connections ==="
if command_exists ss; then
    ss -tap state established
elif command_exists netstat; then
    netstat -tapn | grep ESTABLISHED
else
    echo "Error: Neither ss nor netstat commands are available"
fi
echo ""

# Check for listening ports
echo "=== Listening Ports ==="
if command_exists ss; then
    ss -tulpn
elif command_exists netstat; then
    netstat -tulpn
else
    echo "Error: Neither ss nor netstat commands are available"
fi
echo ""

# Check for connections by process
echo "=== Connections by Process ==="
if command_exists lsof; then
    lsof -i -P -n
else
    echo "Warning: lsof command not available, skipping connections by process"
fi
echo ""

# Check for unusual ports or connections
echo "=== Unusual Ports (non-standard) ==="
if command_exists ss; then
    # Exclude common ports and show others
    ss -tulpn | grep -v -E ':(22|53|80|443|3306|5432|25|587|993|995|110|143|8080|8443)[ \t]'
elif command_exists netstat; then
    netstat -tulpn | grep -v -E ':(22|53|80|443|3306|5432|25|587|993|995|110|143|8080|8443)[ \t]'
else
    echo "Error: Neither ss nor netstat commands are available"
fi
echo ""

# Check for connections to suspicious IPs (example range, adapt as needed)
echo "=== Checking for Suspicious External Connections ==="
if command_exists ss; then
    echo "Connections to non-standard ports:"
    ss -tap | grep -v -E ':(22|53|80|443|3306|5432|25|587|993|995|110|143|8080|8443)[ \t]'
elif command_exists netstat; then
    netstat -tapn | grep -v -E ':(22|53|80|443|3306|5432|25|587|993|995|110|143|8080|8443)[ \t]'
else
    echo "Error: Neither ss nor netstat commands are available"
fi
echo ""

# Check for any connections with a high number of connections from a single source
echo "=== Potential Connection Flooding ==="
if command_exists ss; then
    echo "Top connection sources:"
    ss -tn | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -10
elif command_exists netstat; then
    netstat -tn | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -10
else
    echo "Error: Neither ss nor netstat commands are available"
fi
echo ""

# Check for processes with suspicious network activity
echo "=== Processes with Network Activity ==="
if command_exists ps && (command_exists ss || command_exists netstat); then
    # Get all processes with network connections
    if command_exists ss; then
        NETPROCS=$(ss -tapn | grep -v "LISTEN\|ESTAB" | awk '{print $6}' | cut -d'"' -f2 | sort | uniq)
    else
        NETPROCS=$(netstat -tapn | grep -v "LISTEN\|ESTABLISHED" | awk '{print $7}' | cut -d'/' -f2 | sort | uniq)
    fi
    
    # Check each process
    for proc in $NETPROCS; do
        if [ -n "$proc" ]; then
            echo "Process: $proc"
            ps aux | grep "$proc" | grep -v grep
        fi
    done
else
    echo "Warning: Required commands not available, skipping suspicious process check"
fi
echo ""

# Check DNS resolution status
echo "=== DNS Resolution Status ==="
if command_exists dig; then
    echo "Testing Google DNS:"
    dig @8.8.8.8 google.com +short
    echo "Testing Cloudflare DNS:"
    dig @1.1.1.1 cloudflare.com +short
elif command_exists nslookup; then
    echo "Testing DNS with nslookup:"
    nslookup google.com
else
    echo "Warning: Neither dig nor nslookup available, skipping DNS resolution test"
fi
echo ""

# Check for network interface status
echo "=== Network Interface Status ==="
if command_exists ip; then
    ip -s link
elif command_exists ifconfig; then
    ifconfig
else
    echo "Warning: Neither ip nor ifconfig commands available, skipping interface status"
fi
echo ""

# Scan for open ports on localhost
echo "=== Local Port Scan Summary ==="
if command_exists nc; then
    for port in 21 22 23 25 53 80 443 445 3306 3389 5432 8080 8443; do
        nc -z -v -w1 127.0.0.1 $port 2>&1 | grep succeeded
    done
else
    echo "Warning: nc command not available, skipping local port scan"
fi

echo "=== Deep Connection Scan Complete ==="
echo "Scan completed at $(date)"
exit 0
