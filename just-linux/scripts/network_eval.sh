#!/bin/sh
# Set strict error handling
set -e

# Check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
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
echo "Analysis mode: Comprehensive"
echo ""

# --- ESTABLISHED CONNECTIONS ANALYSIS ---
print_header "ESTABLISHED CONNECTION ANALYSIS"

if command_exists ss; then
  print_subheader "External Connection Summary (by destination)"
  ss -tapn state established | grep -v "127.0.0." |
    awk '{print $5" "$6}' | sed 's/:[^:]*$//' |
    sort | uniq -c | sort -nr | head -15
elif command_exists netstat; then
  print_subheader "External Connection Summary (by destination)"
  netstat -tapn | grep ESTABLISHED | grep -v "127.0.0." |
    awk '{print $5" "$7}' | sed 's/:[^:]*$//' |
    sort | uniq -c | sort -nr | head -15
else
  echo "WARNING: Neither ss nor netstat available. Connection analysis skipped."
fi

print_subheader "Connections by Process (count)"
if command_exists ss; then
  ss -tap | grep -v LISTEN | awk -F'"' '{for(i=1;i<=NF;i++) if($i ~ /^[a-zA-Z0-9]/) print $i}' |
    sort | uniq -c | sort -nr |
    while read line; do
      count=$(echo "$line" | awk '{print $1}')
      proc=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')
      if [ "$count" -gt 20 ]; then
        echo "$count connections: $proc [HIGH]"
      elif [ "$count" -gt 5 ]; then
        echo "$count connections: $proc [MODERATE]"
      else
        echo "$count connections: $proc"
      fi
    done
fi
echo ""

# --- SERVICE CATEGORIZATION SUMMARY ---
print_header "SERVICE CATEGORIZATION SUMMARY"

# Create service category summary
if command_exists ss || command_exists netstat; then
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

  # Get listening ports and their categories
  if command_exists ss; then
    # Use a more robust extraction method that works with various ss formats
    LISTEN_PORTS=$(ss -tulpn | grep -E 'LISTEN|UNCONN' |
                 awk '{for(i=1;i<=NF;i++) if($i ~ /:[0-9]+$/) print $i}' |
                 sed 's/.*://' | grep -o '[0-9]*' | sort -u)
  else
    LISTEN_PORTS=$(netstat -tulpn | grep -E 'LISTEN|.*UDP' |
                 awk '{for(i=1;i<=NF;i++) if($i ~ /:[0-9]+$/) print $i}' |
                 sed 's/.*://' | grep -o '[0-9]*' | sort -u)
  fi

  # Count services by category
  for port in $LISTEN_PORTS; do
    category=$(categorize_service "$port")
    case "$category" in
      "DIRECTORY/AUTH")
        AUTH_COUNT=$((AUTH_COUNT + 1))
        ;;
      "WEB")
        WEB_COUNT=$((WEB_COUNT + 1))
        ;;
      "REMOTE ACCESS")
        REMOTE_COUNT=$((REMOTE_COUNT + 1))
        ;;
      "DATABASE")
        DB_COUNT=$((DB_COUNT + 1))
        ;;
      "MAIL")
        MAIL_COUNT=$((MAIL_COUNT + 1))
        ;;
      "FILE SHARING")
        FILE_COUNT=$((FILE_COUNT + 1))
        ;;
      "DNS/RESOLUTION")
        DNS_COUNT=$((DNS_COUNT + 1))
        ;;
      "APPLICATION")
        APP_COUNT=$((APP_COUNT + 1))
        ;;
      "MGMT/MONITOR")
        MGMT_COUNT=$((MGMT_COUNT + 1))
        ;;
      "TIME")
        TIME_COUNT=$((TIME_COUNT + 1))
        ;;
      *)
        OTHER_COUNT=$((OTHER_COUNT + 1))
        ;;
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
  echo ""

  # For each category with services, list the specific services
  if command_exists ss; then
    if [ $AUTH_COUNT -gt 0 ]; then
      print_subheader "Authentication & Directory Services"
      ss -tulpn | grep LISTEN | sort -t: -k2 -n |
        while read line; do
          port=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /:[0-9]+$/) print $i}' |
             sed 's/.*://' | grep -o '[0-9]*' | head -1)
          if [ "$(categorize_service "$port")" = "DIRECTORY/AUTH" ]; then
            proc=$(echo "$line" | grep -o 'users:.*' | sed 's/users://' | sed 's/","/ /g' | sed 's/"//g')
            addr=$(echo "$line" | awk '{print $4}')
            case "$port" in
              88)   echo "Kerberos Authentication ($addr): $proc" ;;
              389)  echo "LDAP Directory Service ($addr): $proc" ;;
              636)  echo "LDAPS Secure Directory ($addr): $proc" ;;
              464)  echo "Kerberos Password ($addr): $proc" ;;
              749)  echo "Kerberos Admin ($addr): $proc" ;;
              *)    echo "Auth Service Port $port ($addr): $proc" ;;
            esac
          fi
        done
      echo ""
    fi

    if [ $WEB_COUNT -gt 0 ]; then
      print_subheader "Web Services"
      ss -tulpn | grep LISTEN | sort -t: -k2 -n |
        while read line; do
          port=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /:[0-9]+$/) print $i}' |
             sed 's/.*://' | grep -o '[0-9]*' | head -1)
          if [ "$(categorize_service "$port")" = "WEB" ]; then
            proc=$(echo "$line" | grep -o 'users:.*' | sed 's/users://' | sed 's/","/ /g' | sed 's/"//g')
            addr=$(echo "$line" | awk '{print $4}')
            case "$port" in
              80)    echo "HTTP Web Service ($addr): $proc" ;;
              443)   echo "HTTPS Secure Web ($addr): $proc" ;;
              8080)  echo "HTTP Alternate ($addr): $proc" ;;
              8443)  echo "HTTPS Alternate ($addr): $proc" ;;
              8000)  echo "Web Service ($addr): $proc" ;;
              *)     echo "Web Service Port $port ($addr): $proc" ;;
            esac
          fi
        done
      echo ""
    fi

    if [ $REMOTE_COUNT -gt 0 ]; then
      print_subheader "Remote Access Services"
      ss -tulpn | grep LISTEN | sort -t: -k2 -n |
        while read line; do
          port=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /:[0-9]+$/) print $i}' |
             sed 's/.*://' | grep -o '[0-9]*' | head -1)
          if [ "$(categorize_service "$port")" = "REMOTE ACCESS" ]; then
            proc=$(echo "$line" | grep -o 'users:.*' | sed 's/users://' | sed 's/","/ /g' | sed 's/"//g')
            addr=$(echo "$line" | awk '{print $4}')
            case "$port" in
              22)    echo "SSH Secure Shell ($addr): $proc" ;;
              23)    echo "Telnet [INSECURE] ($addr): $proc" ;;
              3389)  echo "RDP Remote Desktop ($addr): $proc" ;;
              *)     echo "Remote Access Port $port ($addr): $proc" ;;
            esac
          fi
        done
      echo ""
    fi

    if [ $APP_COUNT -gt 0 ]; then
      print_subheader "Application Services"
      ss -tulpn | grep LISTEN | sort -t: -k2 -n |
        while read line; do
          port=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /:[0-9]+$/) print $i}' |
             sed 's/.*://' | grep -o '[0-9]*' | head -1)
          if [ "$(categorize_service "$port")" = "APPLICATION" ]; then
            proc=$(echo "$line" | grep -o 'users:.*' | sed 's/users://' | sed 's/","/ /g' | sed 's/"//g')
            addr=$(echo "$line" | awk '{print $4}')
            case "$port" in
              8005)  echo "Tomcat Shutdown ($addr): $proc" ;;
              8009)  echo "Tomcat AJP ($addr): $proc" ;;
              9090)  echo "Cockpit Web Console ($addr): $proc" ;;
              *)     echo "Application Port $port ($addr): $proc" ;;
            esac
          fi
        done
      echo ""
    fi

    if [ $MGMT_COUNT -gt 0 ]; then
      print_subheader "Management & Monitoring Services"
      ss -tulpn | grep LISTEN | sort -t: -k2 -n |
        while read line; do
          port=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /:[0-9]+$/) print $i}' |
             sed 's/.*://' | grep -o '[0-9]*' | head -1)
          if [ "$(categorize_service "$port")" = "MGMT/MONITOR" ]; then
            proc=$(echo "$line" | grep -o 'users:.*' | sed 's/users://' | sed 's/","/ /g' | sed 's/"//g')
            addr=$(echo "$line" | awk '{print $4}')
            case "$port" in
              10000)  echo "Webmin ($addr): $proc" ;;
              28038|38401)  echo "Webmin/Usermin ($addr): $proc" ;;
              *)      echo "Management Port $port ($addr): $proc" ;;
            esac
          fi
        done
      echo ""
    fi

    if [ $DNS_COUNT -gt 0 ]; then
      print_subheader "DNS & Name Resolution Services"
      ss -tulpn | grep LISTEN | sort -t: -k2 -n |
        while read line; do
          port=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /:[0-9]+$/) print $i}' |
             sed 's/.*://' | grep -o '[0-9]*' | head -1)
          if [ "$(categorize_service "$port")" = "DNS/RESOLUTION" ]; then
            proc=$(echo "$line" | grep -o 'users:.*' | sed 's/users://' | sed 's/","/ /g' | sed 's/"//g')
            addr=$(echo "$line" | awk '{print $4}')
            case "$port" in
              53)    echo "DNS Service ($addr): $proc" ;;
              5353)  echo "mDNS/Avahi ($addr): $proc" ;;
              5355)  echo "LLMNR Service ($addr): $proc" ;;
              *)     echo "Name Resolution Port $port ($addr): $proc" ;;
            esac
          fi
        done
      echo ""
    fi
  fi
else
  echo "WARNING: Neither ss nor netstat available. Service categorization skipped."
fi
echo ""

# --- LISTENING PORTS ANALYSIS ---
print_header "LISTENING PORTS ANALYSIS"

if command_exists ss; then
  print_subheader "TCP Listening Ports"
  ss -tlpn | grep LISTEN | sort -t: -k2 -n |
    while read line; do
      port=$(echo "$line" | awk '{print $4}' | sed 's/.*://')
      proc=$(echo "$line" | grep -o 'users:.*' | sed 's/users://' | sed 's/","/ /g' | sed 's/"//g')
      addr=$(echo "$line" | awk '{print $4}')

      # Get service category
      category=$(categorize_service "$port")

      # Classify port security risk
      case "$port" in
        22|53|80|443|3306|5432|25|587|993|995|110|143|8080|8443|631)
          echo "Port $port ($addr): $proc [STANDARD] [$category]"
          ;;
        21|23|445|1433|3389|5900|6379|27017)
          echo "Port $port ($addr): $proc [REVIEW] [$category]"
          ;;
        *)
          echo "Port $port ($addr): $proc [UNUSUAL] [$category]"
          ;;
      esac
    done

  print_subheader "UDP Listening Ports"
  ss -ulpn | grep -v LISTEN | sort -t: -k2 -n |
    while read line; do
      port=$(echo "$line" | awk '{print $4}' | sed 's/.*://')
      proc=$(echo "$line" | grep -o 'users:.*' | sed 's/users://' | sed 's/","/ /g' | sed 's/"//g')
      addr=$(echo "$line" | awk '{print $4}')

      # Get service category
      category=$(categorize_service "$port")

      # Classify port security risk for UDP
      case "$port" in
        53|123|5353|67|68|137|138|1900|5355)
          echo "Port $port ($addr): $proc [STANDARD] [$category]"
          ;;
        *)
          echo "Port $port ($addr): $proc [REVIEW] [$category]"
          ;;
      esac
    done
elif command_exists netstat; then
  print_subheader "TCP Listening Ports"
  netstat -tlpn | grep LISTEN | sort -t: -k2 -n |
    while read line; do
      port=$(echo "$line" | awk '{print $4}' | sed 's/.*://')
      proc=$(echo "$line" | awk '{print $7}')
      addr=$(echo "$line" | awk '{print $4}')

      # Get service category
      category=$(categorize_service "$port")

      # Classify port security risk
      case "$port" in
        22|53|80|443|3306|5432|25|587|993|995|110|143|8080|8443|631)
          echo "Port $port ($addr): $proc [STANDARD] [$category]"
          ;;
        21|23|445|1433|3389|5900|6379|27017)
          echo "Port $port ($addr): $proc [REVIEW] [$category]"
          ;;
        *)
          echo "Port $port ($addr): $proc [UNUSUAL] [$category]"
          ;;
      esac
    done

  print_subheader "UDP Listening Ports"
  netstat -ulpn | grep -v LISTEN | sort -t: -k2 -n |
    while read line; do
      port=$(echo "$line" | awk '{print $4}' | sed 's/.*://')
      proc=$(echo "$line" | awk '{print $7}')
      addr=$(echo "$line" | awk '{print $4}')

      # Get service category
      category=$(categorize_service "$port")

      # Classify port security risk for UDP
      case "$port" in
        53|123|5353|67|68|137|138|1900|5355)
          echo "Port $port ($addr): $proc [STANDARD] [$category]"
          ;;
        *)
          echo "Port $port ($addr): $proc [REVIEW] [$category]"
          ;;
      esac
    done
else
  echo "WARNING: Neither ss nor netstat available. Listening port analysis skipped."
fi
echo ""

# --- PROCESS NETWORK ACTIVITY ANALYSIS ---
print_header "PROCESS NETWORK ACTIVITY ANALYSIS"

print_subheader "Processes With Most Connections"
if command_exists ss && command_exists ps; then
  # Extract processes with network connections
  if command_exists ss; then
    NETPROCS=$(ss -tap | grep -v "LISTEN" | grep "users:" | grep -o '"[^"]*"' | tr -d '"' | sort | uniq)
  elif command_exists netstat; then
    NETPROCS=$(netstat -tap | grep -v "LISTEN" | awk '{print $NF}' | grep "/" | cut -d'/' -f2 | sort | uniq)
  else
    NETPROCS=""
  fi

  # Check each process
  for proc in $NETPROCS; do
    if [ -n "$proc" ]; then
      if command_exists ss; then
        CONN_COUNT=$(ss -tap | grep -c "\"$proc\"" 2>/dev/null || echo 0)
      else
        CONN_COUNT=$(netstat -tap | grep -c "/$proc" 2>/dev/null || echo 0)
      fi

      # Get process details
      PROC_DETAILS=$(ps aux | grep "$proc" | grep -v grep | head -1)
      USER=$(echo "$PROC_DETAILS" | awk '{print $1}')
      PID=$(echo "$PROC_DETAILS" | awk '{print $2}')
      CPU=$(echo "$PROC_DETAILS" | awk '{print $3}')
      MEM=$(echo "$PROC_DETAILS" | awk '{print $4}')

      # Format based on connection count
      if [ "$CONN_COUNT" -gt 20 ]; then
        echo "$proc (PID: $PID, User: $USER) - $CONN_COUNT connections [HIGH] - CPU: $CPU%, MEM: $MEM%"
      elif [ "$CONN_COUNT" -gt 10 ]; then
        echo "$proc (PID: $PID, User: $USER) - $CONN_COUNT connections [MODERATE] - CPU: $CPU%, MEM: $MEM%"
      elif [ "$CONN_COUNT" -gt 0 ]; then
        echo "$proc (PID: $PID, User: $USER) - $CONN_COUNT connections - CPU: $CPU%, MEM: $MEM%"
      fi
    fi
  done
else
  echo "WARNING: Required commands not available. Process network analysis skipped."
fi
echo ""

# --- SUSPICIOUS CONNECTION PATTERNS ---
print_header "SUSPICIOUS CONNECTION PATTERNS"

print_subheader "Top External IPs"
if command_exists ss; then
  ss -tan | grep ESTAB | awk '{print $5}' | cut -d: -f1 | grep -v "^$" | grep -v "\[" | sort | uniq -c | sort -nr | head -10
elif command_exists netstat; then
  netstat -tan | grep ESTAB | awk '{print $5}' | cut -d: -f1 | grep -v "^$" | sort | uniq -c | sort -nr | head -10
fi

print_subheader "High Port Connections (potentially suspicious)"
if command_exists ss; then
  ss -tan | grep ESTAB | grep -E ':[4-9][0-9]{4}|:[1-9][0-9]{5}' | sort -t: -k2 -n | head -10
elif command_exists netstat; then
  netstat -tan | grep ESTAB | grep -E ':[4-9][0-9]{4}|:[1-9][0-9]{5}' | sort -t: -k2 -n | head -10
fi
echo ""

# --- INTERFACES AND ROUTES ---
print_header "NETWORK INTERFACE SUMMARY"

if command_exists ip; then
  print_subheader "Network Interfaces"
  ip -br addr show
else
  print_subheader "Network Interfaces"
  ifconfig -a | grep -E '^[a-z]|inet ' | grep -v 'inet6'
fi

print_subheader "Routing Table"
if command_exists ip; then
  ip route
else
  netstat -rn
fi
echo ""

# --- DNS CONFIGURATION ---
print_header "DNS CONFIGURATION"

print_subheader "Resolver Configuration"
if [ -f /etc/resolv.conf ]; then
  cat /etc/resolv.conf | grep -v '^#' | grep .
fi

print_subheader "DNS Resolution Test"
if command_exists dig; then
  echo "Google DNS test:"
  dig @8.8.8.8 google.com +short
elif command_exists nslookup; then
  echo "Google DNS test:"
  nslookup google.com | grep Address | grep -v '#' | head -1
fi
echo ""

# --- LOCAL PORT SCAN ---
print_header "LOCAL PORT SCAN SUMMARY"
if command_exists ss; then
  print_subheader "Open Ports on localhost"
  ss -tulpn | grep LISTEN | grep -E '127.0.0.1|::1' | sort -t: -k2 -n |
    while read line; do
      port=$(echo "$line" | awk '{print $4}' | sed 's/.*://')
      proc=$(echo "$line" | grep -o 'users:.*' | sed 's/users://' | sed 's/","/ /g' | sed 's/"//g')
      category=$(categorize_service "$port")
      echo "Port $port: $proc [$category]"
    done
elif command_exists netstat; then
  print_subheader "Open Ports on localhost"
  netstat -tulpn | grep LISTEN | grep -E '127.0.0.1|::1' | sort -t: -k2 -n |
    while read line; do
      port=$(echo "$line" | awk '{print $4}' | sed 's/.*://')
      proc=$(echo "$line" | awk '{print $7}')
      category=$(categorize_service "$port")
      echo "Port $port: $proc [$category]"
    done
fi
echo ""

# --- SECURITY ROLE PROFILE ---
print_header "SYSTEM SECURITY ROLE PROFILE"

# Attempt to determine system role based on services
# Fix by storing command results in variables and ensuring they're numeric
AUTH_COUNT=$(ss -tulpn 2>/dev/null | grep -c -E ':88|:389|:636' 2>/dev/null || echo 0)
WEB_COUNT=$(ss -tulpn 2>/dev/null | grep -c -E ':80|:443' 2>/dev/null || echo 0)
APP_COUNT=$(ss -tulpn 2>/dev/null | grep -c -E ':8080|:8443|:8009' 2>/dev/null || echo 0)
DB_COUNT=$(ss -tulpn 2>/dev/null | grep -c -E ':3306|:5432|:1521' 2>/dev/null || echo 0)
MAIL_COUNT=$(ss -tulpn 2>/dev/null | grep -c -E ':25|:587|:110|:143|:993|:995' 2>/dev/null || echo 0)

# Ensure values are numeric
AUTH_COUNT=$(echo "$AUTH_COUNT" | tr -cd '0-9')
WEB_COUNT=$(echo "$WEB_COUNT" | tr -cd '0-9')
APP_COUNT=$(echo "$APP_COUNT" | tr -cd '0-9')
DB_COUNT=$(echo "$DB_COUNT" | tr -cd '0-9')
MAIL_COUNT=$(echo "$MAIL_COUNT" | tr -cd '0-9')

# Set defaults if empty
[ -z "$AUTH_COUNT" ] && AUTH_COUNT=0
[ -z "$WEB_COUNT" ] && WEB_COUNT=0
[ -z "$APP_COUNT" ] && APP_COUNT=0
[ -z "$DB_COUNT" ] && DB_COUNT=0
[ -z "$MAIL_COUNT" ] && MAIL_COUNT=0

# Now use the clean numeric values in conditions
if [ "$AUTH_COUNT" -gt 1 ]; then
  echo "LIKELY ROLE: DIRECTORY/AUTHENTICATION SERVER"
  echo "This system appears to be running directory services (LDAP) and Kerberos authentication."
  echo "Security recommendations:"
  echo "- Ensure LDAPS (636) is used rather than unencrypted LDAP (389) where possible"
  echo "- Verify Kerberos configuration is using strong encryption"
  echo "- Check for proper access controls to directory services"
  echo ""
elif [ "$WEB_COUNT" -gt 1 ] && [ "$APP_COUNT" -gt 1 ]; then
  echo "LIKELY ROLE: WEB APPLICATION SERVER"
  echo "This system appears to be running web services with application server components."
  echo "Security recommendations:"
  echo "- Ensure web applications are regularly patched and updated"
  echo "- Verify proper TLS configuration on HTTPS ports"
  echo "- Consider implementing a web application firewall"
  echo "- Check for unnecessary exposed admin interfaces (Tomcat, etc.)"
  echo ""
elif [ "$DB_COUNT" -gt 0 ]; then
  echo "LIKELY ROLE: DATABASE SERVER"
  echo "This system appears to be running database services."
  echo "Security recommendations:"
  echo "- Restrict database access to specific IP addresses where possible"
  echo "- Ensure databases are regularly backed up and patches applied"
  echo "- Verify proper authentication mechanisms are enforced"
  echo ""
elif [ "$MAIL_COUNT" -gt 2 ]; then
  echo "LIKELY ROLE: MAIL SERVER"
  echo "This system appears to be running mail services."
  echo "Security recommendations:"
  echo "- Implement proper SPF, DKIM, and DMARC records"
  echo "- Ensure TLS is properly configured for mail transport"
  echo "- Monitor for suspicious mail relay attempts"
  echo ""
else
  echo "LIKELY ROLE: MULTI-PURPOSE SERVER"
  echo "This system appears to be running multiple types of services."
  echo "Security recommendations:"
  echo "- Consider separating services to different servers where appropriate"
  echo "- Ensure each service is properly secured and isolated"
  echo "- Implement network segmentation to protect critical services"
  echo ""
fi

# --- CONCLUSION ---
print_header "SECURITY ANALYSIS SUMMARY"

# Count suspicious ports
if command_exists ss; then
  SUSPICIOUS_PORTS=$(ss -tulpn | grep -v -E ':(22|53|80|443|3306|5432|25|587|993|995|110|143|8080|8443|631)[ \t]' | wc -l)
  HIGH_CONN_PROCS=$(ss -tan | grep ESTAB | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -10 | awk '$1 > 10 {count++} END {print count}')
elif command_exists netstat; then
  SUSPICIOUS_PORTS=$(netstat -tulpn | grep -v -E ':(22|53|80|443|3306|5432|25|587|993|995|110|143|8080|8443|631)[ \t]' | wc -l)
  HIGH_CONN_PROCS=$(netstat -tan | grep ESTAB | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -10 | awk '$1 > 10 {count++} END {print count}')
else
  SUSPICIOUS_PORTS="Unknown"
  HIGH_CONN_PROCS="Unknown"
fi

echo "Analysis completed at $(timestamp)"
echo "Suspicious ports found: $SUSPICIOUS_PORTS"
echo "High-connection processes: $HIGH_CONN_PROCS"
echo ""

exit 0
