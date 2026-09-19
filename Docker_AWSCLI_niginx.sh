#!/bin/bash

set -Eeuo pipefail

# Log all User Data output
LOG_FILE="/var/log/ec2-user-data-setup.log"
exec > >(tee -a "$LOG_FILE" | logger -t ec2-user-data -s 2>/dev/console) 2>&1

export DEBIAN_FRONTEND=noninteractive

echo "Starting Ubuntu EC2 initialization..."

# User Data runs as root
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must run as root."
    exit 1
fi

# Update Ubuntu packages
apt-get update
apt-get upgrade -y

# Install required utilities
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    unzip

# Detect Ubuntu release information
source /etc/os-release

UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
DOCKER_ARCHITECTURE="$(dpkg --print-architecture)"

if [[ -z "$UBUNTU_CODENAME" ]]; then
    echo "Unable to detect Ubuntu release codename."
    exit 1
fi

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker's official APT repository
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME}
Components: stable
Architectures: ${DOCKER_ARCHITECTURE}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# Refresh package metadata
apt-get update

# Install Docker Engine, Docker CLI, Compose and Buildx
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Start Docker now and enable it after reboot
systemctl enable --now docker

# Add the default Ubuntu EC2 user to the Docker group
if id ubuntu >/dev/null 2>&1; then
    usermod -aG docker ubuntu
else
    echo "The ubuntu user was not found."
    exit 1
fi

# Detect CPU architecture for AWS CLI installation
case "$(uname -m)" in
    x86_64)
        AWS_CLI_ARCH="x86_64"
        ;;
    aarch64|arm64)
        AWS_CLI_ARCH="aarch64"
        ;;
    *)
        echo "Unsupported CPU architecture: $(uname -m)"
        exit 1
        ;;
esac

# Download and install the latest AWS CLI version 2
AWS_CLI_TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$AWS_CLI_TEMP_DIR"' EXIT

curl -fsSL \
    "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_CLI_ARCH}.zip" \
    -o "${AWS_CLI_TEMP_DIR}/awscliv2.zip"

unzip -q \
    "${AWS_CLI_TEMP_DIR}/awscliv2.zip" \
    -d "${AWS_CLI_TEMP_DIR}"

"${AWS_CLI_TEMP_DIR}/aws/install" --update

# Verify Docker installation
docker --version
docker compose version
systemctl is-active --quiet docker

# Verify AWS CLI installation
aws --version

echo "Docker installation completed successfully."
echo "Docker Compose installation completed successfully."
echo "AWS CLI installation completed successfully."
echo "Ubuntu EC2 initialization completed."
