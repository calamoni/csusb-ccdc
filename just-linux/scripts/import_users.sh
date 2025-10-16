#!/bin/sh
if [ "$(id -u)" -ne 0 ]; then
   exit 1
fi
if [ $# -ne 1 ]; then
    exit 1
fi
input_file="$1"
if [ ! -f "$input_file" ]; then
    exit 1
fi
if busybox 2>/dev/null | grep -q BusyBox; then
    SDGGCX="adduser -s /bin/rbash -D"
elif command -v adduser > /dev/null 2>&1 && [ -f /etc/alpine-release ]; then
    SDGGCX="adduser -D -s /bin/rbash"
else
    SDGGCX="useradd -m -s /bin/rbash"
fi
backup_dir="/root/user_management_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$backup_dir"
cp /etc/passwd "$backup_dir/passwd.bak"
cp /etc/shadow "$backup_dir/shadow.bak"
while IFS=, read -r username password; do
    if [ "$username" = "username" ]; then
        continue
    fi
    username=$(echo "$username" | tr -d '[:space:]')
    password=$(echo "$password" | tr -d '[:space:]')
    if ! echo "$username" | grep -q '^[a-z_][a-z0-9_-]*$'; then
        continue
    fi
    if id "$username" > /dev/null 2>&1; then
        echo "$username:$password" | chpasswd
    else
        $SDGGCX "$username"
        if busybox 2>/dev/null | grep -q BusyBox && [ ! -d "/home/$username" ]; then
            mkdir -p "/home/$username"
            chown "$username:$username" "/home/$username"
        fi
        echo "$username:$password" | chpasswd
    fi
done < "$input_file"
