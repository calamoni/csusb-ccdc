#!/bin/sh

# Script to extract hostname and IP mappings from Ansible hosts.ini file
# Usage: ./get_host_mappings.sh [path/to/hosts.ini]

# Set the hosts file path from argument or use default
HOSTS_FILE=${1:-"hosts.ini"}

# Check if the file exists
if [ ! -f "$HOSTS_FILE" ]; then
    echo "Error: Hosts file '$HOSTS_FILE' not found"
    exit 1
fi

echo "Hostname to IP Address Mappings"
echo "-------------------------------"

# Parse the hosts file using grep and sed
# Look for lines that contain ansible_host= but don't start with a semicolon or whitespace and semicolon
grep -v "^[[:space:]]*;" "$HOSTS_FILE" | grep "ansible_host=" | 
while read -r line; do
    # Extract hostname (first word)
    hostname=$(echo "$line" | awk '{print $1}')
    
    # Extract IP address using sed
    ip=$(echo "$line" | sed -n 's/.*ansible_host=\([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\).*/\1/p')
    
    if [ -n "$hostname" ] && [ -n "$ip" ]; then
        # Print with formatting (20 chars for hostname column)
        printf "%-20s : %s\n" "$hostname" "$ip"
    fi
done