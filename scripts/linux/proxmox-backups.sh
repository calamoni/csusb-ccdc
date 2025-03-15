#!/bin/bash
set -e

# Configuration
CONFIG_FILE="/etc/proxmox-snapshot-manager.conf"
CRON_FILE="/etc/cron.d/proxmox-snapshots"
LOG_FILE="/var/log/proxmox-snapshot-manager.log"

# Default values
DEFAULT_NODE="pve" # Default node name
DEFAULT_KEEP=5     # Default number of snapshots to keep

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Functions
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    log "[ERROR] $1"
    exit 1
}

success() {
    echo -e "${GREEN}$1${NC}"
    log "$1"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
    log "[WARNING] $1"
}

info() {
    echo -e "${BLUE}$1${NC}"
}

# Ensure we have required commands
check_requirements() {
    for cmd in qm pvesh grep awk sed dirname mkdir; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command not found: $cmd"
        fi
    done
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        # If no config file, set default values
        PROXMOX_NODE="$DEFAULT_NODE"
        PROXMOX_KEEP="$DEFAULT_KEEP"
        
        # Determine node name automatically if running on Proxmox
        if [[ -f "/etc/pve/storage.cfg" ]]; then
            # We're on a Proxmox server
            HOSTNAME=$(hostname -s)
            if pvesh get /nodes/$HOSTNAME &>/dev/null; then
                PROXMOX_NODE="$HOSTNAME"
            fi
        fi
        
        create_config
    fi
}

# Create configuration file
create_config() {
    cat > "$CONFIG_FILE" << EOF
# Proxmox Snapshot Manager Configuration
PROXMOX_NODE="$PROXMOX_NODE"
PROXMOX_KEEP="$PROXMOX_KEEP"
EOF
    chmod 600 "$CONFIG_FILE"
    success "Configuration saved to $CONFIG_FILE"
}

# Initialize setup
init_setup() {
    echo -e "${BOLD}Proxmox Snapshot Manager Setup${NC}"
    echo "Please enter your Proxmox configuration:"
    
    # Get available nodes
    local available_nodes=$(pvesh get /nodes | grep -o '"node":"[^"]*"' | cut -d'"' -f4 | sort)
    
    echo -e "\nAvailable nodes on this Proxmox cluster:"
    echo "$available_nodes" | sed 's/^/  - /'
    
    read -p "Node Name [$DEFAULT_NODE]: " input_node
    PROXMOX_NODE=${input_node:-$DEFAULT_NODE}
    
    read -p "Default snapshots to keep [$DEFAULT_KEEP]: " input_keep
    PROXMOX_KEEP=${input_keep:-$DEFAULT_KEEP}
    
    create_config
    
    echo -e "\nVerifying node access..."
    if ! pvesh get /nodes/$PROXMOX_NODE > /dev/null; then
        warn "Could not access node $PROXMOX_NODE. Please check the node name."
    else
        success "Successfully verified node $PROXMOX_NODE!"
    fi
}

# Execute Proxmox API command
execute_api() {
    local method="$1"
    local path="$2"
    shift 2
    
    pvesh "$method" "$path" "$@"
}

# List all VMs
list_vms() {
    echo -e "${BOLD}Virtual Machines:${NC}"
    
    # Print header
    printf "%-8s %-30s %-20s %-10s\n" "VMID" "NAME" "STATUS" "NODE"
    printf "%-8s %-30s %-20s %-10s\n" "----" "----" "------" "----"
    
    # Directly get VM info using qm command
    qm list | tail -n +2 | while read -r vmid name status memory uptime; do
        # Skip header line if present
        if [[ $vmid == "VMID" ]]; then
            continue
        fi
        
        # Get node for this VM
        node=$(pvesh get /cluster/resources --type vm | grep "\"vmid\":$vmid" | grep -o '"node":"[^"]*"' | cut -d'"' -f4)
        
        printf "%-8s %-30s %-20s %-10s\n" "$vmid" "$name" "$status" "${node:-$PROXMOX_NODE}"
    done
}

# List snapshots for a VM
# List snapshots for a VM
list_snapshots() {
    local vmid="$1"
    if [[ -z "$vmid" ]]; then
        error "VM ID is required"
    fi
    echo -e "${BOLD}Snapshots for VM $vmid:${NC}"
    # Print header
    printf "%-30s %-20s %-40s\n" "NAME" "CREATED" "DESCRIPTION"
    printf "%-30s %-20s %-40s\n" "----" "-------" "-----------"
    
    # Capture the output of qm listsnapshot
    local snapshots_output=$(qm listsnapshot "$vmid")
    
    # Check if any snapshots were found
    if ! echo "$snapshots_output" | grep -q -v "current"; then
        echo "No snapshots found."
        return
    fi
    
    # Parse the output line by line
    echo "$snapshots_output" | while read -r line; do
        # Skip empty lines
        if [[ -z "$line" ]]; then
            continue
        fi
        
        # Extract snapshot name - directly using awk which is safer than sed for this purpose
        local name=$(echo "$line" | awk '{print $2}')
        
        # If the extraction didn't work, try another approach for the tree format
        if [[ -z "$name" || "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            # This handles the arrow notation format
            name=$(echo "$line" | grep -o '`-> [^ ]\+' | cut -d' ' -f2)
            
            # If that still didn't work, try one more approach
            if [[ -z "$name" ]]; then
                # Match anything after the arrow until whitespace
                name=$(echo "$line" | grep -o '`-> [^ ]\+' | sed 's/`-> //')
            fi
        fi
        
        # Skip "current" as it's not a real snapshot
        if [[ "$name" == "current" ]]; then
            continue
        fi
        
        # Extract timestamp if it exists
        local timestamp=$(echo "$line" | grep -o "[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}" || echo "N/A")
        
        # Extract description from the line (everything after the timestamp)
        local line_description=""
        if [[ "$line" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})\ +(.+)$ ]]; then
            line_description="${BASH_REMATCH[2]}"
        fi
        
        # Try to get a more detailed description using pvesh if needed
        local description="$line_description"
        if [[ -z "$description" || "$description" == "no-description" ]]; then
            local snapshot_info=$(pvesh get "/nodes/$PROXMOX_NODE/qemu/$vmid/snapshot/$name" 2>/dev/null || echo "")
            if [[ -n "$snapshot_info" ]]; then
                local pvesh_description=$(echo "$snapshot_info" | grep -o '"description":"[^"]*"' | cut -d'"' -f4 || echo "")
                if [[ -n "$pvesh_description" ]]; then
                    description="$pvesh_description"
                fi
            fi
        fi
        
        # If description is still empty, show "no description"
        if [[ -z "$description" ]]; then
            description="no description"
        fi
        
        # Display the snapshot info
        printf "%-30s %-20s %-40s\n" "$name" "$timestamp" "$description"
    done
}

# Create a snapshot
create_snapshot() {
    local vmid="$1"
    local name="$2"
    local description="${3:-Snapshot created by proxmox-snapshot-manager}"
    
    if [[ -z "$vmid" || -z "$name" ]]; then
        error "VM ID and snapshot name are required"
    fi
    
    echo "Creating snapshot '$name' for VM $vmid..."
    qm snapshot "$vmid" "$name" --description "$description"
    success "Snapshot created successfully!"
}

# Delete a snapshot
delete_snapshot() {
    local vmid="$1"
    local name="$2"
    
    if [[ -z "$vmid" || -z "$name" ]]; then
        error "VM ID and snapshot name are required"
    fi
    
    echo "Deleting snapshot '$name' from VM $vmid..."
    qm delsnapshot "$vmid" "$name"
    success "Snapshot deleted successfully!"
}

# Set up a recurring snapshot
set_recurring_snapshot() {
    local vmid="$1"
    local prefix="$2"
    local schedule="$3"
    local keep="${4:-$PROXMOX_KEEP}"
    
    if [[ -z "$vmid" || -z "$prefix" || -z "$schedule" ]]; then
        error "VM ID, snapshot name prefix, and schedule are required"
    fi
    
    # Handle simplified input format (just a number for daily at that hour)
    if [[ "$schedule" =~ ^[0-9]+$ ]]; then
        # It's just a number, interpret as daily at that hour
        schedule="0 $schedule * * *"
        info "Interpreted schedule as daily at hour $schedule (every day at ${schedule%% *}:00)"
    # Handle simplified weekly format (day@hour)
    elif [[ "$schedule" =~ ^[0-6]@[0-9]+$ ]]; then
        local day=${schedule%%@*}
        local hour=${schedule##*@}
        schedule="0 $hour * * $day"
        info "Interpreted schedule as weekly on day $day at $hour:00"
    else
        # Validate cron format - ensure exactly 5 fields separated by spaces
        if ! echo "$schedule" | grep -Eq '^([0-9,\-\*/]+)\s+([0-9,\-\*/]+)\s+([0-9,\-\*/]+)\s+([0-9,\-\*/]+)\s+([0-9,\-\*/]+)$'; then
            error "Invalid cron schedule format. Example: '0 3 * * *' for daily at 3 AM. Must have 5 fields separated by spaces."
        fi
    fi
    
    # Create the pruning script
    local script_path="/usr/local/bin/proxmox-snapshot-$vmid-$prefix"
    
    cat > "$script_path" << EOF
#!/bin/bash
# Auto-generated snapshot script for VM $vmid
# Created by proxmox-snapshot-manager

# Create snapshot with timestamp
DATE=\$(date +%Y%m%d-%H%M%S)
SNAPSHOT_NAME="${prefix}-\$DATE"

# Log file
LOG_FILE="$LOG_FILE"

# Node (explicitly set to avoid inheritance issues)
PROXMOX_NODE="$PROXMOX_NODE"

# Log function
log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" >> "\$LOG_FILE"
}

# Create the snapshot
log "Creating snapshot \$SNAPSHOT_NAME for VM $vmid"
qm snapshot $vmid "\$SNAPSHOT_NAME" --description "Auto snapshot created at \$(date)"

# Prune old snapshots, keeping only the most recent $keep
log "Pruning old snapshots for VM $vmid, keeping $keep most recent"
SNAPSHOTS=$(qm listsnapshot "$vmid" | grep -v "current" | awk '{print $2}' | grep "^$prefix" | sort)

# Count snapshots
SNAPSHOT_COUNT=\$(echo "\$SNAPSHOTS" | grep -v "^$" | wc -l)

# If we have more than $keep snapshots, delete the oldest ones
if [ "\$SNAPSHOT_COUNT" -gt "$keep" ]; then
    TO_DELETE=\$((\$SNAPSHOT_COUNT - $keep))
    if [ "\$TO_DELETE" -gt 0 ]; then
        log "Need to delete \$TO_DELETE snapshots"
        for snapshot in \$(echo "\$SNAPSHOTS" | head -n \$TO_DELETE); do
            if [ -n "\$snapshot" ]; then
                log "Deleting old snapshot \$snapshot from VM $vmid"
                qm delsnapshot $vmid "\$snapshot" --force
                sleep 2  # Add a small delay to avoid potential race conditions
            fi
        done
    fi
fi

log "Snapshot maintenance complete for VM $vmid"
EOF
    
    chmod +x "$script_path"
    
    # Add cron entry - ensure proper format with spaces between all cron fields
    # Check if schedule has 5 fields, with spaces between them
    if [[ $(echo "$schedule" | wc -w) -ne 5 ]]; then
        error "Invalid cron schedule format: '$schedule'. Must have 5 fields separated by spaces."
    fi
    
    local cron_entry="$schedule root $script_path > /dev/null 2>> $LOG_FILE"
    
    # Remove any existing cron entry for this VM and prefix
    if [[ -f "$CRON_FILE" ]]; then
        sed -i "/proxmox-snapshot-$vmid-$prefix/d" "$CRON_FILE"
    else
        touch "$CRON_FILE"
        chmod 644 "$CRON_FILE"
    fi
    
    # Add the new cron entry
    echo "$cron_entry" >> "$CRON_FILE"
    
    # Ensure the log file exists and is writable
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    success "Recurring snapshot set up for VM $vmid"
    echo "Schedule: $schedule"
    echo "Name prefix: $prefix"
    echo "Keep last: $keep snapshots"
    
    # Ask if user wants to create an initial snapshot now
    read -p "Do you want to create an initial snapshot now? (y/N): " create_initial
    if [[ "$create_initial" == "y" || "$create_initial" == "Y" ]]; then
        echo "Creating initial snapshot..."
        # Ensure variables are passed to the script, particularly PROXMOX_NODE
        export PROXMOX_NODE="$PROXMOX_NODE"
        # Run the generated script immediately to create the first snapshot
        "$script_path"
        success "Initial snapshot created"
    fi
}

# List recurring snapshots
list_recurring_snapshots() {
    echo -e "${BOLD}Recurring Snapshots:${NC}"
    
    if [[ ! -f "$CRON_FILE" ]]; then
        echo "No recurring snapshots configured."
        return
    fi
    
    echo -e "VM ID\tPrefix\tSchedule\tKeep\tScript"
    echo -e "-----\t------\t--------\t----\t------"
    
    # Read file line by line to handle any format issues
    while IFS= read -r line; do
        if [[ "$line" =~ proxmox-snapshot-[0-9]+- ]]; then
            # Extract each part more carefully
            # First, get the script path
            if [[ "$line" =~ (/usr/local/bin/proxmox-snapshot-[0-9]+-[a-zA-Z0-9_-]+) ]]; then
                script="${BASH_REMATCH[1]}"
                
                # Extract schedule (first 5 fields)
                schedule=$(echo "$line" | awk '{print $1, $2, $3, $4, $5}')
                
                # Extract VMID and prefix from script path
                vmid=$(echo "$script" | grep -oP "proxmox-snapshot-\K[0-9]+")
                prefix=$(echo "$script" | grep -oP "proxmox-snapshot-[0-9]+-\K[^/]+")
                
                # Get the keep value from the script content
                if [[ -f "$script" ]]; then
                    keep=$(grep -A 20 "keeping" "$script" | grep -oP "most recent \K[0-9]+" | head -1)
                    
                    echo -e "$vmid\t$prefix\t$schedule\t$keep\t$script"
                else
                    echo -e "$vmid\t$prefix\t$schedule\tN/A\t$script (file missing)"
                fi
            fi
        fi
    done < "$CRON_FILE"
}

# Delete a recurring snapshot
delete_recurring_snapshot() {
    local vmid="$1"
    local prefix="$2"
    
    if [[ -z "$vmid" || -z "$prefix" ]]; then
        error "VM ID and snapshot prefix are required"
    fi
    
    local script_path="/usr/local/bin/proxmox-snapshot-$vmid-$prefix"
    
    # Ask for confirmation about deleting all snapshots
    read -p "Do you also want to delete all snapshots with prefix '$prefix'? (y/N): " delete_snapshots
    
    # Remove cron entry
    if [[ -f "$CRON_FILE" ]]; then
        if grep -q "$script_path" "$CRON_FILE"; then
            sed -i "\\|$script_path|d" "$CRON_FILE"
            rm -f "$script_path"
            success "Recurring snapshot for VM $vmid with prefix '$prefix' deleted"
            
            # If user wants to delete all snapshots with this prefix
            if [[ "$delete_snapshots" == "y" || "$delete_snapshots" == "Y" ]]; then
                echo "Fetching existing snapshots with prefix '$prefix'..."
                # Get list of snapshots with this prefix
		SNAPSHOTS=$(qm listsnapshot "$vmid" | grep -v "current" | awk '{print $2}' | grep "^$prefix" | sort)

                if [[ -n "$SNAPSHOTS" ]]; then
                    # Count snapshots
                    SNAPSHOT_COUNT=$(echo "$SNAPSHOTS" | grep -v "^$" | wc -l)
                    echo "Found $SNAPSHOT_COUNT snapshots to delete."
                    
                    # Delete each snapshot
                    for snapshot in $SNAPSHOTS; do
                        if [[ -n "$snapshot" ]]; then
                            echo "Deleting snapshot '$snapshot'..."
                            qm delsnapshot $vmid "$snapshot" --force
                            sleep 2  # Add a small delay to avoid potential race conditions
                        fi
                    done
                    
                    success "All snapshots with prefix '$prefix' have been deleted"
                else
                    warn "No snapshots found with prefix '$prefix'"
                fi
            fi
        else
            error "No recurring snapshot found for VM $vmid with prefix '$prefix'"
        fi
    else
        error "No recurring snapshots configured"
    fi
}

# Show TUI menu
show_menu() {
    while true; do
        clear
        echo -e "${BOLD}╔════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}║      Proxmox Snapshot Manager          ║${NC}"
        echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"
        echo
        echo -e "${BOLD}Node:${NC} $PROXMOX_NODE"
        echo
        echo -e "${BOLD}Main Menu:${NC}"
        echo "1) List Virtual Machines"
        echo "2) Manage Snapshots"
        echo "3) Configure Recurring Snapshots"
        echo "4) View Configured Recurring Snapshots"
        echo "5) Change Configuration"
        echo "q) Quit"
        echo
        read -p "Select an option: " main_choice
        
        case "$main_choice" in
            1)
                clear
                list_vms
                echo
                read -p "Enter VM ID to manage (or press Enter to return): " vmid
                if [[ -n "$vmid" ]]; then
                    while true; do
                        clear
                        echo -e "${BOLD}Managing VM $vmid${NC}"
                        echo
                        echo "1) List Snapshots"
                        echo "2) Create Snapshot"
                        echo "3) Delete Snapshot"
                        echo "4) Setup Recurring Snapshot"
                        echo "5) Return to main menu"
                        echo
                        read -p "Select an option: " vm_choice
                        
                        case "$vm_choice" in
                            1)
                                clear
                                list_snapshots "$vmid"
                                echo
                                read -p "Press Enter to continue..."
                                ;;
                            2)
                                clear
                                echo -e "${BOLD}Create Snapshot for VM $vmid${NC}"
                                read -p "Snapshot name: " snap_name
                                read -p "Description (optional): " snap_desc
                                
                                if [[ -n "$snap_name" ]]; then
                                    create_snapshot "$vmid" "$snap_name" "$snap_desc"
                                else
                                    error "Snapshot name is required"
                                fi
                                
                                echo
                                read -p "Press Enter to continue..."
                                ;;
                            3)
                                clear
                                list_snapshots "$vmid"
                                echo
                                read -p "Enter snapshot name to delete: " del_name
                                
                                if [[ -n "$del_name" ]]; then
                                    read -p "Are you sure you want to delete snapshot '$del_name'? (y/N): " confirm
                                    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                                        delete_snapshot "$vmid" "$del_name"
                                    fi
                                fi
                                
                                echo
                                read -p "Press Enter to continue..."
                                ;;
                            4)
                                clear
                                echo -e "${BOLD}Setup Recurring Snapshot for VM $vmid${NC}"
                                echo "Examples of cron schedules:"
                                echo " - Daily at 3 AM: 0 3 * * *"
                                echo " - Weekly on Sunday at 2 AM: 0 2 * * 0"
                                echo " - Monthly on the 1st at 1 AM: 0 1 1 * *"
                                echo " - Or simply enter a number (e.g. '3') for daily at that hour"
                                echo " - Or day@hour (e.g. '0@2') for weekly on that day at that hour"
                                echo
                                read -p "Snapshot name prefix: " rec_prefix
                                read -p "Cron schedule: " rec_schedule
                                read -p "Number of snapshots to keep [$PROXMOX_KEEP]: " rec_keep
                                rec_keep=${rec_keep:-$PROXMOX_KEEP}
                                
                                if [[ -n "$rec_prefix" && -n "$rec_schedule" ]]; then
                                    set_recurring_snapshot "$vmid" "$rec_prefix" "$rec_schedule" "$rec_keep"
                                else
                                    error "Snapshot prefix and schedule are required"
                                fi
                                
                                echo
                                read -p "Press Enter to continue..."
                                ;;
                            5)
                                break
                                ;;
                            *)
                                warn "Invalid option"
                                sleep 1
                                ;;
                        esac
                    done
                fi
                ;;
            2)
                clear
                read -p "Enter VM ID: " vmid
                
                if [[ -n "$vmid" ]]; then
                    clear
                    echo -e "${BOLD}Snapshots for VM $vmid:${NC}"
                    list_snapshots "$vmid"
                    
                    echo
                    echo "1) Create Snapshot"
                    echo "2) Delete Snapshot"
                    echo "3) Return to main menu"
                    echo
                    read -p "Select an option: " snap_choice
                    
                    case "$snap_choice" in
                        1)
                            read -p "Snapshot name: " snap_name
                            read -p "Description (optional): " snap_desc
                            
                            if [[ -n "$snap_name" ]]; then
                                create_snapshot "$vmid" "$snap_name" "$snap_desc"
                            else
                                error "Snapshot name is required"
                            fi
                            ;;
                        2)
                            read -p "Enter snapshot name to delete: " del_name
                            
                            if [[ -n "$del_name" ]]; then
                                read -p "Are you sure you want to delete snapshot '$del_name'? (y/N): " confirm
                                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                                    delete_snapshot "$vmid" "$del_name"
                                fi
                            fi
                            ;;
                        *)
                            ;;
                    esac
                fi
                
                echo
                read -p "Press Enter to continue..."
                ;;
            3)
                clear
                list_vms
                echo
                read -p "Enter VM ID for recurring snapshot: " vmid
                
                if [[ -n "$vmid" ]]; then
                    echo -e "${BOLD}Setup Recurring Snapshot for VM $vmid${NC}"
                    echo "Examples of cron schedules:"
                    echo " - Daily at 3 AM: 0 3 * * *"
                    echo " - Weekly on Sunday at 2 AM: 0 2 * * 0"
                    echo " - Monthly on the 1st at 1 AM: 0 1 1 * *"
                    echo " - Or simply enter a number (e.g. '3') for daily at that hour"
                    echo " - Or day@hour (e.g. '0@2') for weekly on that day at that hour"
                    echo
                    read -p "Snapshot name prefix: " rec_prefix
                    read -p "Cron schedule: " rec_schedule
                    read -p "Number of snapshots to keep [$PROXMOX_KEEP]: " rec_keep
                    rec_keep=${rec_keep:-$PROXMOX_KEEP}
                    
                    if [[ -n "$rec_prefix" && -n "$rec_schedule" ]]; then
                        set_recurring_snapshot "$vmid" "$rec_prefix" "$rec_schedule" "$rec_keep"
                    else
                        error "Snapshot prefix and schedule are required"
                    fi
                fi
                
                echo
                read -p "Press Enter to continue..."
                ;;
            4)
                clear
                list_recurring_snapshots
                echo
                echo "1) Delete a recurring snapshot"
                echo "2) Return to main menu"
                echo
                read -p "Select an option: " rec_choice
                
                if [[ "$rec_choice" == "1" ]]; then
                    read -p "Enter VM ID: " del_vmid
                    read -p "Enter snapshot prefix: " del_prefix
                    
                    if [[ -n "$del_vmid" && -n "$del_prefix" ]]; then
                        read -p "Are you sure you want to delete this recurring snapshot? (y/N): " confirm
                        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                            delete_recurring_snapshot "$del_vmid" "$del_prefix"
                        fi
                    fi
                fi
                
                echo
                read -p "Press Enter to continue..."
                ;;
            5)
                init_setup
                echo
                read -p "Press Enter to continue..."
                ;;
            q|Q)
                echo "Exiting Proxmox Snapshot Manager"
                exit 0
                ;;
            *)
                warn "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Show help
show_help() {
    echo -e "${BOLD}Proxmox Snapshot Manager${NC}"
    echo "A utility for managing Proxmox VMs and setting recurring snapshots"
    echo
    echo "Usage: $0 [OPTION]"
    echo
    echo "Options:"
    echo "  --help, -h             Show this help message"
    echo "  --init                 Configure the tool"
    echo "  --list-vms             List all virtual machines"
    echo "  --list-snapshots VMID  List snapshots for a VM"
    echo "  --create-snapshot VMID NAME [DESC]"
    echo "                         Create a snapshot"
    echo "  --delete-snapshot VMID NAME"
    echo "                         Delete a snapshot"
    echo "  --set-recurring VMID PREFIX SCHEDULE [KEEP]"
    echo "                         Set up a recurring snapshot"
    echo "  --list-recurring       List all recurring snapshots"
    echo "  --delete-recurring VMID PREFIX [--delete-all]"
    echo "                         Delete a recurring snapshot"
    echo "                         Add --delete-all to also remove all snapshots with this prefix"
    echo
    echo "If no option is provided, the interactive menu will be shown."
}

# Main
main() {
    # Check if root (required for cron access)
    if [[ $EUID -ne 0 && "$1" != "--help" && "$1" != "-h" ]]; then
        error "This script must be run as root to manage cron jobs"
    fi
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    # Check requirements
    check_requirements
    
    # Process command line arguments
    if [[ $# -eq 0 ]]; then
        load_config
        show_menu
    else
        case "$1" in
            --help|-h)
                show_help
                ;;
            --init)
                init_setup
                ;;
            --list-vms)
                load_config
                list_vms
                ;;
            --list-snapshots)
                if [[ -z "$2" ]]; then
                    error "VM ID is required"
                fi
                load_config
                list_snapshots "$2"
                ;;
            --create-snapshot)
                if [[ -z "$2" || -z "$3" ]]; then
                    error "VM ID and snapshot name are required"
                fi
                load_config
                create_snapshot "$2" "$3" "$4"
                ;;
            --delete-snapshot)
                if [[ -z "$2" || -z "$3" ]]; then
                    error "VM ID and snapshot name are required"
                fi
                load_config
                delete_snapshot "$2" "$3"
                ;;
            --set-recurring)
                if [[ -z "$2" || -z "$3" || -z "$4" ]]; then
                    error "VM ID, snapshot prefix, and schedule are required"
                fi
                load_config
                # Handle non-interactive CLI usage - always create initial snapshot when using CLI
                set_recurring_snapshot "$2" "$3" "$4" "$5"
                
                # When called from command line, automatically create initial snapshot
                echo "Creating initial snapshot for CLI usage..."
                # Load configuration first to ensure PROXMOX_NODE is properly set
                load_config
                # Then run the snapshot script
                "/usr/local/bin/proxmox-snapshot-$2-$3"
                success "Initial snapshot created for VM $2"
                ;;
            --list-recurring)
                load_config
                list_recurring_snapshots
                ;;
            --delete-recurring)
                if [[ -z "$2" || -z "$3" ]]; then
                    error "VM ID and snapshot prefix are required"
                fi
                
                load_config
                
                # CLI mode for delete-recurring, automate without prompt
                local vmid="$2"
                local prefix="$3"
                local script_path="/usr/local/bin/proxmox-snapshot-$vmid-$prefix"
                
                # For CLI usage, check for --delete-all flag in 4th position
                if [[ "$4" == "--delete-all" ]]; then
                    # Remove cron entry
                    if [[ -f "$CRON_FILE" ]]; then
                        if grep -q "$script_path" "$CRON_FILE"; then
                            sed -i "\\|$script_path|d" "$CRON_FILE"
                            rm -f "$script_path"
                            success "Recurring snapshot for VM $vmid with prefix '$prefix' deleted"
                            
                            echo "Fetching existing snapshots with prefix '$prefix'..."
                            # Get list of snapshots with this prefix
                            SNAPSHOTS=$(pvesh get "/nodes/$PROXMOX_NODE/qemu/$vmid/snapshot" | grep -o "name:[^,]*$prefix[^,]*" | cut -d':' -f2 | tr -d '"' | grep -v "current" | sort)
                            
                            if [[ -n "$SNAPSHOTS" ]]; then
                                # Count snapshots
                                SNAPSHOT_COUNT=$(echo "$SNAPSHOTS" | grep -v "^$" | wc -l)
                                echo "Found $SNAPSHOT_COUNT snapshots to delete."
                                
                                # Delete each snapshot
                                for snapshot in $SNAPSHOTS; do
                                    if [[ -n "$snapshot" ]]; then
                                        echo "Deleting snapshot '$snapshot'..."
                                        qm delsnapshot $vmid "$snapshot" --force
                                        sleep 2  # Add a small delay
                                    fi
                                done
                                
                                success "All snapshots with prefix '$prefix' have been deleted"
                            else
                                warn "No snapshots found with prefix '$prefix'"
                            fi
                        else
                            error "No recurring snapshot found for VM $vmid with prefix '$prefix'"
                        fi
                    else
                        error "No recurring snapshots configured"
                    fi
                else
                    # Default behavior when --delete-all flag is not specified
                    delete_recurring_snapshot "$2" "$3"
                fi
                ;;
            *)
                error "Unknown option: $1. Use --help to see available options."
                ;;
        esac
    fi
}

main "$@"
