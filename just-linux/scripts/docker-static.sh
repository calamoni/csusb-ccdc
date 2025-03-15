#!/bin/bash

# docker-static-install.sh
# Script to install Docker Engine from static binaries
# Based on Docker's official documentation

set -e

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run as root or with sudo privileges${NC}"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    # Check kernel version
    kernel_version=$(uname -r | cut -d. -f1,2)
    if (( $(echo "$kernel_version < 3.10" | bc -l) )); then
        echo -e "${RED}Kernel version 3.10 or higher is required. Current version: $(uname -r)${NC}"
        exit 1
    fi
    echo "✓ Kernel version: $(uname -r)"
    
    # Check for iptables
    if ! command -v iptables &> /dev/null || [[ $(iptables --version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1) < "1.4" ]]; then
        echo -e "${RED}iptables version 1.4 or higher is required${NC}"
        exit 1
    fi
    echo "✓ iptables: $(iptables --version | head -1)"
    
    # Check for git
    if ! command -v git &> /dev/null; then
        echo -e "${RED}git is required${NC}"
        exit 1
    fi
    echo "✓ git: $(git --version)"
    
    # Check for ps
    if ! command -v ps &> /dev/null; then
        echo -e "${RED}ps executable is required${NC}"
        exit 1
    fi
    echo "✓ ps available"
    
    # Check for xz
    if ! command -v xz &> /dev/null; then
        echo -e "${RED}XZ Utils are required${NC}"
        exit 1
    fi
    echo "✓ XZ Utils: $(xz --version | head -1)"
    
    # Check for properly mounted cgroupfs
    if ! grep -q cgroup /proc/mounts; then
        echo -e "${YELLOW}Warning: No cgroups mount detected. Docker may not work correctly.${NC}"
    else
        echo "✓ cgroupfs mounted"
    fi
    
    echo -e "${GREEN}All prerequisites satisfied${NC}"
}

# Function to determine system architecture
get_arch() {
    arch=$(uname -m)
    case $arch in
        x86_64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        armv7l|armv7)
            echo "armhf"
            ;;
        s390x)
            echo "s390x"
            ;;
        *)
            echo -e "${RED}Unsupported architecture: $arch${NC}"
            exit 1
            ;;
    esac
}

# Function to download and install Docker static binaries
install_docker() {
    arch=$(get_arch)
    echo -e "${YELLOW}Detected architecture: $arch${NC}"
    
    # Ask for the version or use latest
    read -p "Enter Docker version to install (or press Enter for latest): " version
    
    if [ -z "$version" ]; then
        version="latest"
        echo "Using latest version"
    fi
    
    # Create temporary directory
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir"
    
    # Download the static binary archive
    echo -e "${YELLOW}Downloading Docker static binaries...${NC}"
    if [ "$version" = "latest" ]; then
        # Get latest version
        latest_url="https://download.docker.com/linux/static/stable/$arch/"
        latest_version=$(curl -s "$latest_url" | grep -o 'docker-[0-9]*\.[0-9]*\.[0-9]*\.tgz' | sort -V | tail -1)
        if [ -z "$latest_version" ]; then
            echo -e "${RED}Failed to determine latest version${NC}"
            exit 1
        fi
        download_url="$latest_url$latest_version"
        version=${latest_version#docker-}
        version=${version%.tgz}
    else
        download_url="https://download.docker.com/linux/static/stable/$arch/docker-$version.tgz"
    fi
    
    echo "Downloading from: $download_url"
    if ! curl -L -o docker.tgz "$download_url"; then
        echo -e "${RED}Failed to download Docker static binaries${NC}"
        exit 1
    fi
    
    # Extract the archive
    echo -e "${YELLOW}Extracting Docker binaries...${NC}"
    tar xzvf docker.tgz
    
    # Copy binaries to /usr/bin
    echo -e "${YELLOW}Installing Docker binaries to /usr/bin...${NC}"
    cp docker/* /usr/bin/
    
    # Clean up
    cd - > /dev/null
    rm -rf "$tmp_dir"
    
    echo -e "${GREEN}Docker $version static binaries installed successfully${NC}"
}

# Function to create systemd service
create_systemd_service() {
    echo -e "${YELLOW}Creating systemd service for Docker...${NC}"
    
    cat > /etc/systemd/system/docker.service << 'EOL'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOL
    
    # Create docker daemon configuration directory
    mkdir -p /etc/docker
    
    # Create default daemon.json
    if [ ! -f /etc/docker/daemon.json ]; then
        echo -e "${YELLOW}Creating default daemon.json...${NC}"
        cat > /etc/docker/daemon.json << 'EOL'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOL
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    echo -e "${GREEN}Docker systemd service created${NC}"
}

# Function to create docker group and add current user
setup_user_permissions() {
    echo -e "${YELLOW}Setting up Docker user permissions...${NC}"
    
    # Create the docker group if it doesn't exist
    if ! getent group docker > /dev/null; then
        groupadd docker
    fi
    
    # Get the current user (if script is run with sudo)
    current_user=${SUDO_USER:-$USER}
    
    # Add the user to the docker group
    if [ "$current_user" != "root" ]; then
        usermod -aG docker "$current_user"
        echo -e "${GREEN}Added user $current_user to the docker group${NC}"
        echo -e "${YELLOW}Note: You may need to log out and back in for group changes to take effect${NC}"
    fi
}

# Function to start Docker service
start_docker() {
    echo -e "${YELLOW}Starting Docker service...${NC}"
    
    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker
    
    # Check if Docker is running
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}Docker service started successfully${NC}"
    else
        echo -e "${RED}Failed to start Docker service${NC}"
        echo "Check the logs with: journalctl -u docker"
        exit 1
    fi
}

# Function to verify Docker installation
verify_docker() {
    echo -e "${YELLOW}Verifying Docker installation...${NC}"
    
    # Run hello-world container
    if docker run --rm hello-world; then
        echo -e "${GREEN}Docker verified successfully!${NC}"
    else
        echo -e "${RED}Docker verification failed${NC}"
        exit 1
    fi
}

# Main function
main() {
    echo -e "${GREEN}=== Docker Static Binary Installation Script ===${NC}"
    
    check_root
    check_prerequisites
    install_docker
    create_systemd_service
    setup_user_permissions
    start_docker
    verify_docker
    
    echo -e "${GREEN}=== Docker installation completed successfully ===${NC}"
    echo -e "${YELLOW}Docker version:${NC} $(docker --version)"
    echo -e "${YELLOW}Docker daemon info:${NC}"
    docker info | head -10
    
    echo -e "\n${GREEN}You can now use Docker!${NC}"
    echo -e "If you're running the script with sudo, remember to log out and back in"
    echo -e "to use Docker without sudo. Alternatively, you can run: ${YELLOW}newgrp docker${NC}"
}

# Run the main function
main
