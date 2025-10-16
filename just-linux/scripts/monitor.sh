#!/bin/sh

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to send console alerts
send_alert() {
    local severity="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file
    echo "[$timestamp] [$severity] $message" >> "${LOG_DIR:-/tmp}/monitor.log"
    
    # Console alert with severity indicator
    case "$severity" in
        "CRITICAL")
            echo "🚨 CRITICAL ALERT [$timestamp]: $message" >&2
            # Try to send to all logged-in users
            if command_exists wall; then
                echo "🚨 CRITICAL ALERT [$timestamp]: $message" | wall 2>/dev/null || true
            fi
            ;;
        "WARNING")
            echo "⚠️  WARNING [$timestamp]: $message" >&2
            ;;
        "INFO")
            echo "ℹ️  INFO [$timestamp]: $message"
            ;;
        *)
            echo "[$timestamp] [$severity]: $message"
            ;;
    esac
}

# Function to check if file change is suspicious
is_suspicious_change() {
    local file_path="$1"
    local event_type="$2"
    
    # Critical system files that should trigger alerts
    case "$file_path" in
        */passwd|*/shadow|*/sudoers*|*/crontab|*/cron.*|*/.ssh/*)
            return 0
            ;;
        */pam.d/*|*/security/*)
            return 0
            ;;
        */www/*|*/var/www/*)
            return 0
            ;;
    esac
    
    # Suspicious event types
    case "$event_type" in
        "DELETE"|"MOVED_FROM"|"DELETE_SELF")
            return 0
            ;;
    esac
    
    return 1
}

# Set up logging directory
LOG_DIR="${LOG_DIR:-/tmp}"
mkdir -p "$LOG_DIR"

# Send startup alert
send_alert "INFO" "File monitoring started - watching critical system files"

# cron monitoring with alerts
{
    inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self /etc/cron.allow 2>/dev/null | while read path action file; do
        send_alert "CRITICAL" "Cron allow file changed: $path/$file ($action)"
    done
} &

{
    inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self /etc/cron.deny 2>/dev/null | while read path action file; do
        send_alert "CRITICAL" "Cron deny file changed: $path/$file ($action)"
    done
} &

{
    inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self /etc/cron.d -r 2>/dev/null | while read path action file; do
        send_alert "WARNING" "Cron directory changed: $path/$file ($action)"
    done
} &

{
    inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self /etc/cron.daily -r 2>/dev/null | while read path action file; do
        send_alert "WARNING" "Cron daily changed: $path/$file ($action)"
    done
} &

{
    inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self /etc/cron.hourly -r 2>/dev/null | while read path action file; do
        send_alert "WARNING" "Cron hourly changed: $path/$file ($action)"
    done
} &

{
    inotifywait -m -e modify /etc/crontab 2>/dev/null | while read path action file; do
        send_alert "CRITICAL" "Crontab modified: $path/$file ($action)"
    done
} &

{
    inotifywait -m -e open /var/spool/cron -r 2>/dev/null | while read path action file; do
        send_alert "INFO" "Cron spool accessed: $path/$file ($action)"
    done
} &

# userspace monitoring with alerts
{
    inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self /etc/group 2>/dev/null | while read path action file; do
        send_alert "CRITICAL" "Group file changed: $path/$file ($action)"
    done
} &

{
    inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self /etc/passwd 2>/dev/null | while read path action file; do
        send_alert "CRITICAL" "Passwd file changed: $path/$file ($action)"
    done
} &

{
    inotifywait -m -e open /etc/shadow 2>/dev/null | while read path action file; do
        send_alert "CRITICAL" "Shadow file accessed: $path/$file ($action)"
    done
} &

{
    inotifywait -m -e open /etc/security/opasswd 2>/dev/null | while read path action file; do
        send_alert "WARNING" "Password history accessed: $path/$file ($action)"
    done
} &

# sudo monitoring with alerts
{
    if command_exists sudo; then
        inotifywait -m -e open "$(which sudo)" 2>/dev/null | while read path action file; do
            send_alert "INFO" "Sudo binary accessed: $path/$file ($action)"
        done
    fi
} &

{
    inotifywait -m -e open /etc/sudoers 2>/dev/null | while read path action file; do
        send_alert "CRITICAL" "Sudoers file accessed: $path/$file ($action)"
    done
} &

{
    inotifywait -m -e open /etc/sudoers.d -r 2>/dev/null | while read path action file; do
        send_alert "WARNING" "Sudoers directory accessed: $path/$file ($action)"
    done
} &

# SSH key monitoring with alerts
{
    inotifywait -m -e open /root/.ssh --exclude authorized_keys -r 2>/dev/null | while read path action file; do
        send_alert "CRITICAL" "Root SSH directory accessed: $path/$file ($action)"
    done
} &

# Monitor user SSH directories
if command_exists fd; then
    fd --type d --glob ".ssh" --base-directory /home 2>/dev/null | while read file; do
        {
            inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self "/home/$file" -r 2>/dev/null | while read path action file; do
                send_alert "WARNING" "User SSH directory changed: $path/$file ($action)"
            done
        } &
    done
else
    for file in $(find /home -name .ssh  2>/dev/null); do
        {
            inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self "$file" -r 2>/dev/null | while read path action file; do
                send_alert "WARNING" "User SSH directory changed: $path/$file ($action)"
            done
        } &
    done
fi
# recon ttp
inotifywait -m -e open "$(which whoami)" &
inotifywait -m -e open "$(which hostnamectl)" &
inotifywait -m -e open /etc/hostname &
# rc modification
inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self /root/.bashrc &
inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self /root/.vimrc &


#pam modification
inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self /etc/pam.d -r &

# run: find /lib/ -name "pam_permit.so" to find where .so files are
# deb default: /lib/x86_64-linux-gnu/security/
if command_exists fd; then
    PAM_PERMIT_PATH=$(fd --type f --glob "pam_permit.so" --base-directory /lib 2>/dev/null | head -1 | sed 's|^|/lib/|')
else
    PAM_PERMIT_PATH=$(find /lib/ -name "pam_permit.so" 2>/dev/null | head -1)
fi
PAM_DIR=$(dirname "$PAM_PERMIT_PATH")
inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self "$PAM_DIR" -r &

#iptables modification
inotifywait -m -e open "$(which iptables)" &
inotifywait -m -e open "$(which xtables-multi)" &

#MOTD
inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self /etc/update-motd.d/ -r &

#GIT
# find / -name .git
if command_exists fd; then
    fd --type d --glob ".git" --base-directory / --one-file-system 2>/dev/null | while read file; do
        GIT_DIR=$(dirname "/$file")
        inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self "$GIT_DIR" -r &
    done
else
    for file in $(find / -name .git  2>/dev/null); do
        GIT_DIR=$(dirname "$file")
        inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self "$GIT_DIR" -r &
    done;
fi


#NETWORK
inotifywait -m -e open /etc/network -r &

# Web root monitoring with alerts
{
    inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self /var/www -r 2>/dev/null | while read path action file; do
        send_alert "WARNING" "Web root changed: $path/$file ($action)"
    done
} &

# User management command monitoring
{
    if command_exists chpasswd; then
        inotifywait -m -e open "$(which chpasswd)" 2>/dev/null | while read path action file; do
            send_alert "CRITICAL" "Password change command accessed: $path/$file ($action)"
        done
    fi
} &

{
    if command_exists useradd; then
        inotifywait -m -e open "$(which useradd)" 2>/dev/null | while read path action file; do
            send_alert "CRITICAL" "User creation command accessed: $path/$file ($action)"
        done
    fi
} &

{
    if command_exists userdel; then
        inotifywait -m -e open "$(which userdel)" 2>/dev/null | while read path action file; do
            send_alert "CRITICAL" "User deletion command accessed: $path/$file ($action)"
        done
    fi
} &

{
    if command_exists usermod; then
        inotifywait -m -e open "$(which usermod)" 2>/dev/null | while read path action file; do
            send_alert "WARNING" "User modification command accessed: $path/$file ($action)"
        done
    fi
} &

{
    if command_exists groupadd; then
        inotifywait -m -e open "$(which groupadd)" 2>/dev/null | while read path action file; do
            send_alert "WARNING" "Group creation command accessed: $path/$file ($action)"
        done
    fi
} &

{
    if command_exists groupdel; then
        inotifywait -m -e open "$(which groupdel)" 2>/dev/null | while read path action file; do
            send_alert "WARNING" "Group deletion command accessed: $path/$file ($action)"
        done
    fi
} &

{
    if command_exists chmod; then
        inotifywait -m -e open "$(which chmod)" 2>/dev/null | while read path action file; do
            send_alert "INFO" "Permission change command accessed: $path/$file ($action)"
        done
    fi
} &

# Database access monitoring
{
    if command_exists mysql; then
        inotifywait -m -e open "$(which mysql)" 2>/dev/null | while read path action file; do
            send_alert "INFO" "MySQL access: $path/$file ($action)"
        done
    fi
} &

{
    if command_exists psql; then
        inotifywait -m -e open "$(which psql)" 2>/dev/null | while read path action file; do
            send_alert "INFO" "PostgreSQL access: $path/$file ($action)"
        done
    fi
} &

{
    if command_exists mongosh; then
        inotifywait -m -e open "$(which mongosh)" 2>/dev/null | while read path action file; do
            send_alert "INFO" "MongoDB access: $path/$file ($action)"
        done
    fi
} &

#check ftproot for modification
#inotifywait -m -e modify,create,delete,attrib,moved_to,moved_from,move_self,delete_self  FTPROOT -r &


# wait for all scripts to exit (should never exit)
wait
