#!/bin/sh

# Set error handling
set -e

# Check if a command exists
command_exists() {
  which "$1" >/dev/null 2>&1
}

# Print section headers with consistent formatting
print_header() {
  echo "============================================================"
  echo "==== $1 ===="
  echo "============================================================"
}

# Print subheaders
print_subheader() {
  echo "---- $1 ----"
}

# Function to categorize services based on port
categorize_service() {
  port=$1

  case "$port" in
    # Authentication & Directory Services
    88|389|636|464|749)
      echo "DIRECTORY/AUTH"
      ;;
    # Web Services
    80|443|8080|8443|8000)
      echo "WEB"
      ;;
    # Remote Access
    22|23|3389)
      echo "REMOTE ACCESS"
      ;;
    # Database Services
    1433|1521|3306|5432|6379|27017|27018|27019)
      echo "DATABASE"
      ;;
    # Mail Services
    25|465|587|110|143|993|995)
      echo "MAIL"
      ;;
    # File Sharing
    21|445|2049|137|138|139)
      echo "FILE SHARING"
      ;;
    # Name Resolution
    53|5353|5355)
      echo "DNS/RESOLUTION"
      ;;
    # Application Services
    8005|8009|8081|8181|9000|9090)
      echo "APPLICATION"
      ;;
    # Monitoring & Management
    161|162|10000|28038|38401)
      echo "MGMT/MONITOR"
      ;;
    # Time Services
    123|323)
      echo "TIME"
      ;;
    # High ports (typically ephemeral)
    [1-9][0-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9][0-9])
      echo "EPHEMERAL"
      ;;
    *)
      echo "OTHER"
      ;;
  esac
}

# Timestamp for the report
timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

# Get hostname for the report
hostname=$(hostname 2>/dev/null || echo "unknown-host")

# Begin the scan
print_header "NETWORK SECURITY ANALYSIS REPORT"
echo "Host: $hostname"
echo "Time: $(timestamp)"
echo "Analysis mode: BusyBox Compatible"
echo ""

# --- ESTABLISHED CONNECTIONS ANALYSIS ---
print_header "ESTABLISHED CONNECTION ANALYSIS"

if command_exists netstat; then
  print_subheader "External Connection Summary (by destination)"
  # BusyBox netstat doesn't support all options, use simpler approach
  netstat -tn | grep ESTABLISHED | grep -v "127.0.0." | 
    while read line; do
      echo "$line" | awk '{print $5}' | cut -d: -f1
    done | sort | uniq -c | sort -nr | head -15
fi

echo ""

# --- SERVICE CATEGORIZATION SUMMARY ---
print_header "SERVICE CATEGORIZATION SUMMARY"

if command_exists netstat; then
  # Initialize counters for service categories
  AUTH_COUNT=0
  WEB_COUNT=0
  REMOTE_COUNT=0
  DB_COUNT=0
  MAIL_COUNT=0
  FILE_COUNT=0
  DNS_COUNT=0
  APP_COUNT=0
  MGMT_COUNT=0
  TIME_COUNT=0
  OTHER_COUNT=0

  # Get listening ports
  # BusyBox netstat typically doesn't support -p, so we just get port info
  netstat -tln | grep LISTEN | 
    while read line; do
      port=$(echo "$line" | awk '{print $4}' | rev | cut -d: -f1 | rev)
      category=$(categorize_service "$port")
      case "$category" in
        "DIRECTORY/AUTH") AUTH_COUNT=$((AUTH_COUNT + 1)) ;;
        "WEB") WEB_COUNT=$((WEB_COUNT + 1)) ;;
        "REMOTE ACCESS") REMOTE_COUNT=$((REMOTE_COUNT + 1)) ;;
        "DATABASE") DB_COUNT=$((DB_COUNT + 1)) ;;
        "MAIL") MAIL_COUNT=$((MAIL_COUNT + 1)) ;;
        "FILE SHARING") FILE_COUNT=$((FILE_COUNT + 1)) ;;
        "DNS/RESOLUTION") DNS_COUNT=$((DNS_COUNT + 1)) ;;
        "APPLICATION") APP_COUNT=$((APP_COUNT + 1)) ;;
        "MGMT/MONITOR") MGMT_COUNT=$((MGMT_COUNT + 1)) ;;
        "TIME") TIME_COUNT=$((TIME_COUNT + 1)) ;;
        *) OTHER_COUNT=$((OTHER_COUNT + 1)) ;;
      esac
    done

  # Display service category summary
  echo "Service role breakdown:"
  [ $AUTH_COUNT -gt 0 ] && echo "- Authentication & Directory Services: $AUTH_COUNT ports"
  [ $WEB_COUNT -gt 0 ] && echo "- Web Services: $WEB_COUNT ports"
  [ $REMOTE_COUNT -gt 0 ] && echo "- Remote Access Services: $REMOTE_COUNT ports"
  [ $DB_COUNT -gt 0 ] && echo "- Database Services: $DB_COUNT ports"
  [ $MAIL_COUNT -gt 0 ] && echo "- Mail Services: $MAIL_COUNT ports"
  [ $FILE_COUNT -gt 0 ] && echo "- File Sharing Services: $FILE_COUNT ports"
  [ $DNS_COUNT -gt 0 ] && echo "- DNS/Name Resolution Services: $DNS_COUNT ports"
  [ $APP_COUNT -gt 0 ] && echo "- Application Services: $APP_COUNT ports"
  [ $MGMT_COUNT -gt 0 ] && echo "- Management/Monitoring Services: $MGMT_COUNT ports"
  [ $TIME_COUNT -gt 0 ] && echo "- Time Services: $TIME_COUNT ports"
  [ $OTHER_COUNT -gt 0 ] && echo "- Other/Unclassified Services: $OTHER_COUNT ports"
fi
echo ""

# --- LISTENING PORTS ANALYSIS ---
print_header "LISTENING PORTS ANALYSIS"

if command_exists netstat; then
  print_subheader "TCP Listening Ports"
  netstat -tln | grep LISTEN | 
    while read line; do
      port=$(echo "$line" | awk '{print $4}' | rev | cut -d: -f1 | rev)
      addr=$(echo "$line" | awk '{print $4}')
      
      # Get service category
      category=$(categorize_service "$port")
      
      # Classify port security risk
      case "$port" in
        22|53|80|443|3306|5432|25|587|993|995|110|143|8080|8443|631)
          echo "Port $port ($addr): [STANDARD] [$category]"
          ;;
        21|23|445|1433|3389|5900|6379|27017)
          echo "Port $port ($addr): [REVIEW] [$category]"
          ;;
        *)
          echo "Port $port ($addr): [UNUSUAL] [$category]"
          ;;
      esac
    done

  print_subheader "UDP Listening Ports"
  netstat -uln | 
    while read line; do
      port=$(echo "$line" | awk '{print $4}' | rev | cut -d: -f1 | rev)
      addr=$(echo "$line" | awk '{print $4}')
      
      # Get service category
      category=$(categorize_service "$port")
      
      # Classify port security risk for UDP
      case "$port" in
        53|123|5353|67|68|137|138|1900|5355)
          echo "Port $port ($addr): [STANDARD] [$category]"
          ;;
        *)
          echo "Port $port ($addr): [REVIEW] [$category]"
          ;;
      esac
    done
fi
echo ""

# --- SUSPICIOUS CONNECTION PATTERNS ---
print_header "SUSPICIOUS CONNECTION PATTERNS"

print_subheader "Top External IPs"
if command_exists netstat; then
  netstat -tn | grep ESTABLISHED | 
    while read line; do
      echo "$line" | awk '{print $5}' | cut -d: -f1
    done | grep -v "^$" | grep -v "127.0.0.1" | sort | uniq -c | sort -nr | head -10
fi

print_subheader "High Port Connections (potentially suspicious)"
if command_exists netstat; then
  netstat -tn | grep ESTABLISHED | grep -E ':[4-9][0-9]{4}|:[1-9][0-9]{5}' | sort | head -10
fi
echo ""

# --- INTERFACES AND ROUTES ---
print_header "NETWORK INTERFACE SUMMARY"

print_subheader "Network Interfaces"
ifconfig | grep -E '^[a-z]|inet addr' | grep -v 'inet6'

print_subheader "Routing Table"
route | grep -v "^Kernel" | grep -v "^Destination"
echo ""

# --- DNS CONFIGURATION ---
print_header "DNS CONFIGURATION"

print_subheader "Resolver Configuration"
if [ -f /etc/resolv.conf ]; then
  cat /etc/resolv.conf | grep -v '^#' | grep .
fi
echo ""

# --- LOCAL PORT SCAN ---
print_header "LOCAL PORT SCAN SUMMARY"
if command_exists netstat; then
  print_subheader "Open Ports on localhost"
  netstat -tln | grep LISTEN | grep -E '127.0.0.1|::1' | 
    while read line; do
      port=$(echo "$line" | awk '{print $4}' | rev | cut -d: -f1 | rev)
      category=$(categorize_service "$port")
      echo "Port $port: [$category]"
    done
fi
echo ""

# --- SECURITY ROLE PROFILE ---
print_header "SYSTEM SECURITY ROLE PROFILE"

# Use basic checks to determine system role based on ports
TCP_PORTS=$(netstat -tln | grep LISTEN | awk '{print $4}' | rev | cut -d: -f1 | rev)
HAS_WEB=0
HAS_DB=0
HAS_MAIL=0
HAS_AUTH=0

for port in $TCP_PORTS; do
  case "$port" in
    80|443|8080|8443) HAS_WEB=1 ;;
    3306|5432|1521) HAS_DB=1 ;;
    25|587|110|143|993|995) HAS_MAIL=1 ;;
    88|389|636) HAS_AUTH=1 ;;
  esac
done

if [ $HAS_AUTH -eq 1 ]; then
  echo "LIKELY ROLE: DIRECTORY/AUTHENTICATION SERVER"
  echo "This system appears to be running directory services (LDAP) and/or Kerberos authentication."
  echo "Security recommendations:"
  echo "- Ensure LDAPS (636) is used rather than unencrypted LDAP (389) where possible"
  echo "- Verify Kerberos configuration is using strong encryption"
  echo "- Check for proper access controls to directory services"
  echo ""
elif [ $HAS_WEB -eq 1 ]; then
  echo "LIKELY ROLE: WEB SERVER"
  echo "This system appears to be running web services."
  echo "Security recommendations:"
  echo "- Ensure web applications are regularly patched and updated"
  echo "- Verify proper TLS configuration on HTTPS ports"
  echo "- Consider implementing a web application firewall"
  echo ""
elif [ $HAS_DB -eq 1 ]; then
  echo "LIKELY ROLE: DATABASE SERVER"
  echo "This system appears to be running database services."
  echo "Security recommendations:"
  echo "- Restrict database access to specific IP addresses where possible"
  echo "- Ensure databases are regularly backed up and patches applied"
  echo "- Verify proper authentication mechanisms are enforced"
  echo ""
elif [ $HAS_MAIL -eq 1 ]; then
  echo "LIKELY ROLE: MAIL SERVER"
  echo "This system appears to be running mail services."
  echo "Security recommendations:"
  echo "- Implement proper SPF, DKIM, and DMARC records"
  echo "- Ensure TLS is properly configured for mail transport"
  echo "- Monitor for suspicious mail relay attempts"
  echo ""
else
  echo "LIKELY ROLE: MULTI-PURPOSE OR SPECIALIZED SERVER"
  echo "This system appears to be running multiple types of services or specialized services."
  echo "Security recommendations:"
  echo "- Ensure each service is properly secured"
  echo "- Implement network restrictions to protect services"
  echo "- Regularly monitor for suspicious activities"
  echo ""
fi

# --- CONCLUSION ---
print_header "SECURITY ANALYSIS SUMMARY"

# Count suspicious ports (simplified for BusyBox)
SUSPICIOUS_PORT_COUNT=$(netstat -tln | grep LISTEN | 
  awk '{print $4}' | rev | cut -d: -f1 | rev | 
  grep -v -E '^(22|53|80|443|3306|5432|25|587|993|995|110|143|8080|8443|631)$' | wc -l)

echo "Analysis completed at $(timestamp)"
echo "Suspicious ports found: $SUSPICIOUS_PORT_COUNT"
echo ""

exit 0
