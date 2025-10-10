#!/bin/bash
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run this script as root (use sudo)"
    exit 1
fi

echo "  ____        _        ____                         ___           _        _ _           ";
echo " |  _ \\  __ _| |_ __ _/ ___| _ __   __ _  ___ ___  |_ _|_ __  ___| |_ __ _| | | ___ _ __ ";
echo " | | | |/ _\` | __/ _\` \\___ \\| '_ \\ / _\` |/ __/ _ \\  | || '_ \\/ __| __/ _\` | | |/ _ \\ '__|";
echo " | |_| | (_| | || (_| |___) | |_) | (_| | (_|  __/  | || | | \\__ \\ || (_| | | |  __/ |   ";
echo " |____/ \\__,_|\\__\\__,_|____/| .__/ \\__,_|\\___\\___| |___|_| |_|___/\\__\\__,_|_|_|\\___|_|   ";
echo "                            |_|                                                          ";
echo

# Prompt for domain name
read -p "Enter the domain name: " domain_name
if [ -z "$domain_name" ]; then
    echo "Error: Domain name cannot be empty"
    exit 1
fi

# Prompt for Github key
read -p "Enter the Github key: " github_key
if [ -z "$github_key" ]; then
    echo "Error: Github key cannot be empty"
    exit 1
fi

# Prompt for License key
read -p "Enter the License key: " license_key
if [ -z "$license_key" ]; then
    echo "Error: License key cannot be empty"
    exit 1
fi

# Prompt for dataspace_app password
read -sp "Enter a new password for dataspace_app user: " password
echo
if [ -z "$password" ]; then
    echo "Error: Password cannot be empty"
    exit 1
fi

# Prompt for UID/GID with 1002 as default
read -p "Enter UID/GID for dataspace_app user (default: 1002): " uid_gid
if [ -z "$uid_gid" ]; then
    uid_gid=1002
fi

# Validate that uid_gid is a number
if ! [[ "$uid_gid" =~ ^[0-9]+$ ]]; then
    echo "Error: UID/GID must be a number"
    exit 1
fi

echo
echo "Creating user..."

# Create the dataspace_app group with specified GID (ignore if exists)
groupadd -g $uid_gid dataspace_app 2>/dev/null || true

# Create a new user called dataspace_app with specified UID and GID
useradd -m -s /bin/bash -u $uid_gid -g $uid_gid dataspace_app 2>/dev/null || true

# Add to sudo group
usermod -aG sudo dataspace_app

# Set password for dataspace_app
echo "dataspace_app:$password" | chpasswd

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    echo "Docker is already installed. Skipping installation."    
else
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm /tmp/get-docker.sh
fi

# Test if docker is running
if docker ps &> /dev/null; then
    echo "Docker is running."
else
    echo "Starting Docker service..."
    systemctl start docker
    systemctl enable docker
fi

# Add dataspace_app to docker group
usermod -aG docker dataspace_app

echo "Setting up DataSpace directory and downloading files..."

# Execute the rest as dataspace_app user
sudo -u dataspace_app bash <<EOSU
set -e

# Go to home directory
cd ~

# Create DataSpace directory
mkdir -p ./DataSpace
cd ./DataSpace

# Create folders first
mkdir -p ./volume/
mkdir -p ./volume/DataSpace_data
mkdir -p ./volume/DataSpace_db_data
mkdir -p ./volume/DataSpace_db_backup
mkdir -p ./volume_backup/
mkdir -p ./caddy/
mkdir -p ./secrets/

# Download resource files
echo "Downloading configuration files..."
wget -q -O startup.sh https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/startup.sh
wget -q -O update.sh https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/update.sh
wget -q -O docker-compose.yml https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/docker-compose.yml
wget -q -O .env https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/.env
wget -q -O Caddyfile https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/Caddyfile
wget -q -O blocked_ips.caddyfile https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/blocked_ips.caddyfile
wget -q -O dataspace-startup.service https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/dataspace-startup.service

# Make scripts executable
chmod +x ./startup.sh
chmod +x ./update.sh

# Update Caddyfile content with domain name and admin email
# Note: Adjust the sed patterns to match your actual placeholders in the files
sed -i "s/{domain_name}/$domain_name/g" ./caddy/Caddyfile 2>/dev/null || true
sed -i "s/{admin_email}/admin@$domain_name/g" ./caddy/Caddyfile 2>/dev/null || true

# Update .env file content with domain name and admin email
sed -i "s/{domain_name}/$domain_name/g" ./.env 2>/dev/null || true
sed -i "s/{admin_email}/admin@$domain_name/g" ./.env 2>/dev/null || true

sed -i "s/{license_key}/$license_key/g" ./.env 2>/dev/null || true

# Update .env file content with USER_ID and GROUP_ID
sed -i "s/{user_id}/$uid_gid/g" ./.env 2>/dev/null || true
sed -i "s/{group_id}/$uid_gid/g" ./.env 2>/dev/null || true

# Save the Github key to a file
echo "$github_key" > ./secrets/gh_key.txt
chmod 600 ./secrets/gh_key.txt

echo "Files downloaded and configured successfully."

EOSU

# Setup systemd service for startup script
echo "Setting up systemd service..."
sudo cp /home/dataspace_app/DataSpace/dataspace-startup.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable dataspace-startup.service

echo
echo "=== Installation Complete ==="
echo
echo "Next steps:"
echo "1. Review and fill in the .env file at /home/dataspace_app/DataSpace/.env"
echo "2. Switch to dataspace_app user: su - dataspace_app"
echo "3. Navigate to DataSpace: cd ~/DataSpace"
echo "4. Run the update script: ./update.sh"
echo
echo "Note: You may need to log out and back in for Docker permissions to take effect."
echo "Or run: newgrp docker"
echo
