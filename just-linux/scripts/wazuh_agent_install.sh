#!/bin/bash


# Usage: ./wazuh_agent_install.sh MANAGER_IP

# Exit on error
set -e

# Function to determine service management system
get_service_manager() {
    if command -v systemctl >/dev/null 2>&1; then
        echo "systemctl"
        elif command -v service >/dev/null 2>&1; then
        echo "service"
        elif command -v rc-service >/dev/null 2>&1; then
        echo "rc-service"
    else
        echo "unknown"
    fi
}

# Function to check if IP is provided
check_ip() {
    if [ -z "$1" ]; then
        echo "Error: IP address not provided"
        echo "Usage: ./install-wazuh.sh <manager_ip>"
        exit 1
    fi
}

# Get the Wazuh manager IP from command line argument
MANAGER_IP=$1
check_ip "$MANAGER_IP"

get_agent_version() {
    # Get architecture
    arch=$(uname -m)
    
    # Get package manager
    if command -v rpm >/dev/null 2>&1; then
        pkg_manager="RPM"
        elif command -v dpkg >/dev/null 2>&1; then
        pkg_manager="DEB"
    else
        echo "Unknown package manager"
        exit 1
    fi
    
    # Determine the exact option
    case "$arch" in
        "x86_64")
            if [ "$pkg_manager" = "RPM" ]; then
                echo "RPM amd64"
                elif [ "$pkg_manager" = "DEB" ]; then
                echo "DEB amd64"
            fi
        ;;
        "aarch64")
            if [ "$pkg_manager" = "RPM" ]; then
                echo "RPM aarch64"
                elif [ "$pkg_manager" = "DEB" ]; then
                echo "DEB aarch64"
            fi
        ;;
        *)
            echo "Unknown architecture: $arch"
            exit 1
        ;;
    esac
}

install_agent() {
    
    version=$(get_agent_version)
    service_manager=$(get_service_manager)
    
    case $version in
        "RPM amd64")
            echo "Installing RPM amd64 version..."
            curl -o wazuh-agent-4.9.2-1.x86_64.rpm https://packages.wazuh.com/4.x/yum/wazuh-agent-4.9.2-1.x86_64.rpm && \
            sudo WAZUH_MANAGER=$MANAGER_IP rpm -ihv wazuh-agent-4.9.2-1.x86_64.rpm
        ;;
        
        "DEB amd64")
            echo "Installing DEB amd64 version..."
            wget https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.9.2-1_amd64.deb && \
            sudo WAZUH_MANAGER=$MANAGER_IP dpkg -i ./wazuh-agent_4.9.2-1_amd64.deb
        ;;
        
        "RPM_aarch64")
            echo "Installing RPM aarch64 version..."
            curl -o wazuh-agent-4.9.2-1.aarch64.rpm https://packages.wazuh.com/4.x/yum/wazuh-agent-4.9.2-1.aarch64.rpm && \
            sudo WAZUH_MANAGER=$MANAGER_IP rpm -ihv wazuh-agent-4.9.2-1.aarch64.rpm
        ;;
        
        "DEB_aarch64")
            echo "Installing DEB aarch64 version..."
            wget https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.9.2-1_arm64.deb && \
            sudo WAZUH_MANAGER=$MANAGER_IP dpkg -i ./wazuh-agent_4.9.2-1_arm64.deb
        ;;
        
        *)
            echo "Error: Unsupported system configuration: ${version}"
            exit 1
        ;;
    esac
    
    # Start and enable Wazuh agent
    case $service_manager in
        "systemctl")
            sudo systemctl daemon-reload
            sudo systemctl enable wazuh-agent
            sudo systemctl start wazuh-agent
        ;;
        "service")
            sudo service wazuh-agent enable
            sudo service wazuh-agent start
        ;;
        "rc-service")
            sudo rc-service wazuh-agent enable
            sudo rc-service wazuh-agent start
        ;;
        *)
            echo "Error: Unsupported service manager: ${service_manager}"
            exit 1
        ;;
    esac
}

# Main execution
main() {
    # Check if script is run as root or with sudo
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root or with sudo"
        exit 1
    fi
    
    echo "Checking linux arch setup..."
    version=$(get_agent_version)
    echo "Linux arch setup: ${version}"
    echo "Installing agent..."
    install_agent
    
}

main
