#!/bin/sh

MYSQL_USER="root"
# Leave password blank if using socket authentication
MYSQL_PASSWORD="StrongPassword123!"
# Set to 1 to actually execute the ALTER commands, 0 to just print them
EXECUTE_COMMANDS=1
# Set to 1 to create a backup of configuration files before modifying
BACKUP_CONFIGS=1

echo "=== MySQL Database Encryption Script for CCDC ==="
echo "This script will encrypt all user databases and tables."

# Password argument handling
if [ -n "$MYSQL_PASSWORD" ]; then
  MYSQL_PWD_ARG="-p$MYSQL_PASSWORD"
else
  MYSQL_PWD_ARG=""
fi

# Function to run MySQL commands
run_mysql_cmd() {
  if [ -n "$MYSQL_PASSWORD" ]; then
    mysql -u "$MYSQL_USER" "$MYSQL_PWD_ARG" -e "$1" --skip-column-names
  else
    mysql -u "$MYSQL_USER" -e "$1" --skip-column-names
  fi
}

# Function to create backups of configuration files
backup_config() {
  file="$1"
  if [ -f "$file" ] && [ "$BACKUP_CONFIGS" -eq 1 ]; then
    backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
    echo "Creating backup of $file to $backup"
    if ! cp "$file" "$backup"; then
      echo "Warning: Failed to create backup of $file"
      return 1
    fi
  fi
  return 0
}

# Step 0: Check MySQL version and encryption support
echo "[0/5] Checking MySQL version and encryption support..."
mysql_version=$(run_mysql_cmd "SELECT VERSION();")
if ! [ "$mysql_version" ]; then
  echo "Error: Failed to connect to MySQL server. Please check credentials and server status."
  exit 1
fi

echo "MySQL version: $mysql_version"
# Extract major.minor version
major_version=$(echo "$mysql_version" | cut -d. -f1)
minor_version=$(echo "$mysql_version" | cut -d. -f2)

# Check if version supports encryption (5.7+ or 8.0+)
if [ "$major_version" -lt 5 ] || { [ "$major_version" -eq 5 ] && [ "$minor_version" -lt 7 ]; }; then
  echo "Error: MySQL version $mysql_version does not support tablespace encryption."
  echo "Encryption requires MySQL 5.7 or later."
  exit 1
fi

# Check if encryption is already enabled
encryption_status=$(run_mysql_cmd "SHOW VARIABLES LIKE 'innodb_file_per_table';" | awk '{print $2}')
if [ "$encryption_status" != "ON" ]; then
  echo "File per table setting not enabled. This script will enable it."
fi

# Check for existing keyring configuration
keyring_plugins=$(run_mysql_cmd "SELECT PLUGIN_NAME FROM information_schema.plugins WHERE PLUGIN_NAME LIKE '%keyring%' AND PLUGIN_STATUS = 'ACTIVE';")
if [ -n "$keyring_plugins" ]; then
  echo "Keyring plugin(s) already active: $keyring_plugins"
  echo "Warning: This script will modify existing keyring configuration."
  echo "Do you want to continue? (y/n): "
  read -r confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Operation cancelled by user."
    exit 0
  fi
fi

# Step 1: Setup keyring if needed
echo "[1/5] Setting up keyring..."

# Create keyring directory
KEYRING_DIR="/var/lib/mysql-keyring"
echo "Creating keyring directory at $KEYRING_DIR..."
if [ ! -d "$KEYRING_DIR" ]; then
  if ! mkdir -p "$KEYRING_DIR" 2>/dev/null; then
    echo "Error: Failed to create keyring directory. Check permissions."
    exit 1
  fi
  chown mysql:mysql "$KEYRING_DIR" 2>/dev/null
  chmod 750 "$KEYRING_DIR" 2>/dev/null
else
  echo "Keyring directory already exists. Checking permissions..."
  # Check ownership and permissions
  owner=$(stat -c "%U:%G" "$KEYRING_DIR" 2>/dev/null || stat -f "%Su:%Sg" "$KEYRING_DIR" 2>/dev/null)
  perms=$(stat -c "%a" "$KEYRING_DIR" 2>/dev/null || stat -f "%Lp" "$KEYRING_DIR" 2>/dev/null)
  
  if [ "$owner" != "mysql:mysql" ]; then
    echo "Warning: Keyring directory not owned by mysql:mysql. Current: $owner"
    echo "Attempting to fix..."
    chown mysql:mysql "$KEYRING_DIR" 2>/dev/null
  fi
  
  if [ "$perms" != "750" ]; then
    echo "Warning: Keyring directory permissions not set to 750. Current: $perms"
    echo "Attempting to fix..."
    chmod 750 "$KEYRING_DIR" 2>/dev/null
  fi
fi

# Find MySQL configuration directory
MYSQL_CONF_DIR="/etc/mysql/mysql.conf.d"
if [ ! -d "$MYSQL_CONF_DIR" ]; then
  MYSQL_CONF_DIR="/etc/mysql/conf.d"
  if [ ! -d "$MYSQL_CONF_DIR" ]; then
    # Try to detect configuration directory
    if [ -d "/etc/my.cnf.d" ]; then
      MYSQL_CONF_DIR="/etc/my.cnf.d"
    elif [ -f "/etc/my.cnf" ]; then
      echo "Found /etc/my.cnf - will add keyring configuration there."
      MYSQL_CONF_DIR="/etc"
    else
      echo "Error: Could not find MySQL configuration directory."
      exit 1
    fi
  fi
fi

echo "Using MySQL configuration directory: $MYSQL_CONF_DIR"

# Check for existing keyring configuration
KEYRING_CONF=""
if [ -f "$MYSQL_CONF_DIR/keyring.cnf" ]; then
  KEYRING_CONF="$MYSQL_CONF_DIR/keyring.cnf"
  echo "Found existing keyring configuration at $KEYRING_CONF"
  
  # Check if it already has keyring_file configuration
  if grep -q "keyring_file_data" "$KEYRING_CONF"; then
    echo "Existing keyring configuration found containing keyring_file_data."
    existing_path=$(grep "keyring_file_data" "$KEYRING_CONF" | sed 's/.*=\s*//')
    echo "Current keyring path: $existing_path"
    
    if [ "$existing_path" != "$KEYRING_DIR/keyring" ]; then
      echo "Warning: This will change keyring path from $existing_path to $KEYRING_DIR/keyring"
      echo "Do you want to continue? (y/n): "
      read -r confirm
      if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Operation cancelled by user."
        exit 0
      fi
    else
      echo "Keyring configuration already points to $KEYRING_DIR/keyring."
    fi
  fi
elif [ -d "$MYSQL_CONF_DIR" ]; then
  KEYRING_CONF="$MYSQL_CONF_DIR/keyring.cnf"
elif [ -f "$MYSQL_CONF_DIR/my.cnf" ]; then
  KEYRING_CONF="$MYSQL_CONF_DIR/my.cnf"
fi

echo "Creating/Updating keyring configuration at $KEYRING_CONF..."
backup_config "$KEYRING_CONF"

# Check if we're modifying an existing file
if [ -f "$KEYRING_CONF" ]; then
  if grep -q "\[mysqld\]" "$KEYRING_CONF"; then
    # Check if keyring configuration already exists
    if grep -q "early-plugin-load=keyring_file.so" "$KEYRING_CONF" && \
       grep -q "keyring_file_data=$KEYRING_DIR/keyring" "$KEYRING_CONF"; then
      echo "Keyring configuration already exists and is properly configured."
    else
      # Add to existing mysqld section
      echo "Adding keyring configuration to existing [mysqld] section..."
      if ! grep -q "early-plugin-load=keyring_file.so" "$KEYRING_CONF"; then
        sed -i '/\[mysqld\]/a early-plugin-load=keyring_file.so' "$KEYRING_CONF"
      fi
      if ! grep -q "keyring_file_data=" "$KEYRING_CONF"; then
        sed -i '/\[mysqld\]/a keyring_file_data='"$KEYRING_DIR"'/keyring' "$KEYRING_CONF"
      else
        # Update existing keyring path
        sed -i 's|keyring_file_data=.*|keyring_file_data='"$KEYRING_DIR"'/keyring|' "$KEYRING_CONF"
      fi
    fi
  else
    # File exists but no mysqld section
    echo "Adding [mysqld] section with keyring configuration..."
    {
      echo ""
      echo "[mysqld]"
      echo "early-plugin-load=keyring_file.so"
      echo "keyring_file_data=$KEYRING_DIR/keyring"
    } >> "$KEYRING_CONF"
  fi
else
  # Create new file
  cat > "$KEYRING_CONF" << EOF
[mysqld]
early-plugin-load=keyring_file.so
keyring_file_data=$KEYRING_DIR/keyring
EOF
fi

# Check global MySQL configuration for conflicting settings
echo "Checking for conflicting configuration settings..."
config_files="/etc/my.cnf /etc/mysql/my.cnf"

for config in $config_files; do
  if [ -f "$config" ]; then
    echo "Checking $config for keyring settings..."
    if grep -q "keyring_file_data" "$config"; then
      echo "Warning: Found existing keyring configuration in $config"
      echo "This might conflict with new settings in $KEYRING_CONF"
      echo "Continue anyway? (y/n): "
      read -r confirm
      if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Operation cancelled by user."
        exit 0
      fi
    fi
  fi
done

echo "Restarting MySQL to apply keyring configuration..."
if ! systemctl restart mysql 2>/dev/null; then
  if ! service mysql restart 2>/dev/null; then
    echo "Warning: Could not restart MySQL using systemctl or service commands."
    echo "You may need to restart MySQL manually for changes to take effect."
    echo "Continue with script anyway? (y/n): "
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
      echo "Operation cancelled by user."
      exit 0
    fi
  fi
fi

# Wait for MySQL to come back
echo "Waiting for MySQL to restart..."
sleep 10

# Try connecting multiple times to handle slow restarts
max_attempts=10
attempt=1
while [ $attempt -le $max_attempts ]; do
  echo "Attempt $attempt to connect to MySQL..."
  if run_mysql_cmd "SELECT VERSION();" >/dev/null 2>&1; then
    echo "Successfully connected to MySQL"
    break
  else
    if [ $attempt -eq $max_attempts ]; then
      echo "Error: Could not connect to MySQL after $max_attempts attempts"
      echo "Please check MySQL status and logs"
      exit 1
    fi
    echo "Waiting for MySQL to become available..."
    sleep 5
    attempt=$((attempt + 1))
  fi
done

# Check if keyring plugin is active
keyring_plugins=$(run_mysql_cmd "SELECT PLUGIN_NAME FROM information_schema.plugins WHERE PLUGIN_NAME LIKE '%keyring%' AND PLUGIN_STATUS = 'ACTIVE';")
if [ -z "$keyring_plugins" ]; then
  echo "Error: No keyring plugins found after restart. Encryption will fail."
  echo "Please check MySQL error log for details at /var/log/mysql/error.log"
  exit 1
else
  echo "Keyring plugin(s) active: $keyring_plugins"
fi

# Step 2: Ensure innodb_file_per_table is enabled
echo "[2/5] Checking and enabling innodb_file_per_table..."
file_per_table=$(run_mysql_cmd "SELECT @@innodb_file_per_table;")
if [ "$file_per_table" = "0" ] || [ "$file_per_table" = "OFF" ]; then
  echo "innodb_file_per_table is disabled. Enabling it now..."
  if ! run_mysql_cmd "SET GLOBAL innodb_file_per_table=1;"; then
    echo "Error: Failed to enable innodb_file_per_table. This is required for encryption."
    exit 1
  fi
  
  # Make it persistent
  echo "Making innodb_file_per_table setting persistent..."
  backup_config "$KEYRING_CONF"
  if grep -q "\[mysqld\]" "$KEYRING_CONF"; then
    if ! grep -q "innodb_file_per_table" "$KEYRING_CONF"; then
      sed -i '/\[mysqld\]/a innodb_file_per_table=1' "$KEYRING_CONF"
    fi
  else
    {
      echo "[mysqld]"
      echo "innodb_file_per_table=1"
    } >> "$KEYRING_CONF"
  fi
else
  echo "innodb_file_per_table is already enabled."
fi

# Step 3: Create master key if needed
echo "[3/5] Creating master encryption key..."
# Check if master key already exists
has_master_key=$(run_mysql_cmd "SELECT COUNT(*) FROM information_schema.INNODB_TABLESPACES_ENCRYPTION;")
if [ -n "$has_master_key" ] && [ "$has_master_key" -gt 0 ]; then
  echo "Master encryption key already exists."
  echo "Rotate master key? (y/n): "
  read -r rotate_key
  if [ "$rotate_key" = "y" ] || [ "$rotate_key" = "Y" ]; then
    if ! run_mysql_cmd "ALTER INSTANCE ROTATE INNODB MASTER KEY;"; then
      echo "Warning: Failed to rotate master key. Will continue with existing key."
    else
      echo "Master encryption key rotated successfully."
    fi
  fi
else
  # Create new master key
  if ! run_mysql_cmd "ALTER INSTANCE ROTATE INNODB MASTER KEY;"; then
    echo "Warning: Failed to create master key. Will try again after checking settings."
    
    # Verify settings are correct
    echo "Verifying MySQL settings..."
    run_mysql_cmd "SET GLOBAL innodb_file_per_table=1;"
    
    echo "Trying master key creation again..."
    if ! run_mysql_cmd "ALTER INSTANCE ROTATE INNODB MASTER KEY;"; then
      echo "Error: Failed to create master encryption key. Encryption will fail."
      echo "Check MySQL error log for details at /var/log/mysql/error.log"
      exit 1
    else
      echo "Master encryption key created successfully on second attempt."
    fi
  else
    echo "Master encryption key created successfully."
  fi
fi

# Step 4: Encrypt all databases
echo "[4/5] Encrypting all databases and tables..."
databases=$(run_mysql_cmd "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys')")

# Detect already encrypted databases/tables
echo "Detecting already encrypted databases and tables..."
if [ "$EXECUTE_COMMANDS" -eq 1 ]; then
  encrypted_dbs=$(run_mysql_cmd "SELECT schema_name FROM information_schema.schemata WHERE default_encryption='YES' AND schema_name NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys');")
  if [ -n "$encrypted_dbs" ]; then
    echo "Found already encrypted databases:"
    echo "$encrypted_dbs" | while read -r db; do
      echo "  - $db"
    done
  else
    echo "No encrypted databases found."
  fi
  
  encrypted_tables=$(run_mysql_cmd "SELECT CONCAT(table_schema, '.', table_name) FROM information_schema.tables WHERE table_schema NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys') AND table_type='BASE TABLE' AND CREATE_OPTIONS LIKE '%ENCRYPTION=\"Y\"%';")
  if [ -n "$encrypted_tables" ]; then
    echo "Found already encrypted tables (sample):"
    count=0
    echo "$encrypted_tables" | while read -r table && [ $count -lt 5 ]; do
      echo "  - $table"
      count=$((count + 1))
    done
    total=$(echo "$encrypted_tables" | wc -l)
    if [ "$total" -gt 5 ]; then
      echo "  ... and $((total - 5)) more"
    fi
  else
    echo "No encrypted tables found."
  fi
fi

encryption_failures=0

for db in $databases; do
  # Check if database is already encrypted
  db_encrypted=$(run_mysql_cmd "SELECT default_encryption FROM information_schema.schemata WHERE schema_name='$db';")
  if [ "$db_encrypted" = "YES" ]; then
    echo "Database $db is already encrypted. Skipping database encryption."
  else
    echo "Encrypting database: $db"
    if [ "$EXECUTE_COMMANDS" -eq 1 ]; then
      if run_mysql_cmd "ALTER DATABASE \`$db\` ENCRYPTION='Y';"; then
        echo "Database $db encrypted successfully"
      else
        echo "Failed to encrypt database $db"
        encryption_failures=$((encryption_failures + 1))
      fi
    else
      echo "ALTER DATABASE \`$db\` ENCRYPTION='Y';"
    fi
  fi
  
  # Encrypt all tables for this database
  tables=$(run_mysql_cmd "SELECT table_name FROM information_schema.tables WHERE table_schema='$db' AND table_type='BASE TABLE'")
  for table in $tables; do
    # Check if table is already encrypted
    table_encrypted=$(run_mysql_cmd "SELECT CREATE_OPTIONS FROM information_schema.tables WHERE table_schema='$db' AND table_name='$table';")
    if echo "$table_encrypted" | grep -q "ENCRYPTION=\"Y\""; then
      echo "  Table $db.$table is already encrypted. Skipping."
    else
      echo "  Encrypting table: $db.$table"
      if [ "$EXECUTE_COMMANDS" -eq 1 ]; then
        if run_mysql_cmd "ALTER TABLE \`$db\`.\`$table\` ENCRYPTION='Y';"; then
          echo "  Table $db.$table encrypted successfully"
        else
          echo "  Failed to encrypt table $db.$table"
          encryption_failures=$((encryption_failures + 1))
        fi
      else
        echo "  ALTER TABLE \`$db\`.\`$table\` ENCRYPTION='Y';"
      fi
    fi
  done
done

# Step 5: Verify encryption status
echo "[5/5] Verifying encryption status..."
if [ "$EXECUTE_COMMANDS" -eq 1 ]; then
  echo "Checking database encryption:"
  mysql -u "$MYSQL_USER" $MYSQL_PWD_ARG -e "SELECT schema_name AS 'Database', default_encryption AS 'Encrypted' FROM information_schema.schemata WHERE schema_name NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys');"
  
  echo "Checking table encryption:"
  mysql -u "$MYSQL_USER" $MYSQL_PWD_ARG -e "SELECT table_schema AS 'Database', table_name AS 'Table', CREATE_OPTIONS FROM information_schema.tables WHERE table_schema NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys') AND table_type='BASE TABLE';"
  
  # More comprehensive check for encryption status
  total_tables=$(run_mysql_cmd "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys') AND table_type='BASE TABLE';")
  encrypted_tables=$(run_mysql_cmd "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys') AND table_type='BASE TABLE' AND CREATE_OPTIONS LIKE '%ENCRYPTION=\"Y\"%';")
  
  # More accurate reporting based on actual table counts
  if [ "$encrypted_tables" = "$total_tables" ]; then
    echo "Success: All $total_tables tables have encryption enabled (ENCRYPTION='Y')."
  else
    unencrypted=$((total_tables - encrypted_tables))
    if [ "$unencrypted" -gt 0 ]; then
      echo "Warning: $unencrypted out of $total_tables tables do not have ENCRYPTION='Y' option set."
    fi
  fi
  
  # Flag based on command execution failures
  if [ $encryption_failures -gt 0 ]; then
    echo "Warning: $encryption_failures encryption operations failed during execution."
    echo "Some tables might not be properly encrypted despite having ENCRYPTION='Y' in their options."
  else
    echo "All encryption operations completed successfully."
  fi
  
  # Verify actual file-based encryption
  echo "Checking physical file encryption status..."
  test_db=$(echo "$databases" | head -n 1)
  if [ -n "$test_db" ]; then
    datadir=$(run_mysql_cmd "SELECT @@datadir;")
    if [ -d "$datadir$test_db" ]; then
      # Check if tablespace files exist
      ibd_count=$(find "$datadir$test_db" -name "*.ibd" | wc -l)
      if [ "$ibd_count" -gt 0 ]; then
        echo "Found $ibd_count tablespace (.ibd) files for database $test_db"
        
        # Try to verify if files are actually encrypted
        echo "Encryption verification:"
        if command -v strings >/dev/null 2>&1; then
          test_file=$(find "$datadir$test_db" -name "*.ibd" | head -n 1)
          if [ -n "$test_file" ]; then
            # Check for InnoDBxxxxxxxPage signature at start of file
            # If encrypted, this shouldn't be visible in plaintext
            if strings "$test_file" | head -n 10 | grep -q "InnoDB"; then
              echo "Warning: Found 'InnoDB' string in tablespace file. File may not be encrypted properly."
              echo "This could indicate that while ENCRYPTION='Y' is set, actual encryption failed."
            else
              echo "Initial checks suggest tablespace files are encrypted."
            fi
          fi
        fi
      else
        echo "No .ibd files found for database $test_db - cannot verify physical encryption"
      fi
    else
      echo "Cannot access data directory for database $test_db"
    fi
  fi
else
  echo "Commands generated but not executed. Set EXECUTE_COMMANDS=1 to execute."
fi

echo "=== Script completed ==="
echo "Security recommendations:"
echo "1. Store this script securely as it contains database credentials"
echo "2. Ensure the keyring directory ($KEYRING_DIR) is properly secured"
echo "3. Consider backing up the keyring file - if lost, encrypted data cannot be recovered"
echo "4. Verify all services still work with encrypted databases"

