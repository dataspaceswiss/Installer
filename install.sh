#!/bin/bash
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run this script as root (use sudo)"
    exit 1
fi

echo "=== DataSpace Installation Script ==="
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

echo
echo "Creating user and installing Docker..."

# Create the dataspace_app group with GID 1002 (ignore if exists)
groupadd -g 1002 dataspace_app 2>/dev/null || true

# Create a new user called dataspace_app with UID and GID 1002
useradd -m -s /bin/bash -u 1002 -g 1002 dataspace_app 2>/dev/null || true

# Add to sudo group
usermod -aG sudo dataspace_app

# Set password for dataspace_app
echo "dataspace_app:$password" | chpasswd

# Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
sh /tmp/get-docker.sh
rm /tmp/get-docker.sh

# Start and enable Docker service
systemctl start docker
systemctl enable docker

# Test if docker is running
docker ps

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
mkdir -p ./volume_backup/
mkdir -p ./caddy/
mkdir -p ./secrets/

# Download resource files
echo "Downloading configuration files..."
wget -q https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/startup.sh
wget -q https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/update.sh
wget -q https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/docker-compose.yml
wget -q https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/.env
wget -q https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/Caddyfile -O ./caddy/Caddyfile
wget -q https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/blocked_ips.caddyfile -O ./caddy/blocked_ips.caddyfile

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

# Save the Github key to a file
echo "$github_key" > ./secrets/gh_key.txt
chmod 600 ./secrets/gh_key.txt

echo "Files downloaded and configured successfully."

EOSU

# Register startup script to execute on boot (as dataspace_app user)
STARTUP_SCRIPT_PATH="/home/dataspace_app/DataSpace/startup.sh"
sudo -u dataspace_app bash <<EOCRON
(crontab -l 2>/dev/null | grep -v "$STARTUP_SCRIPT_PATH" ; echo "@reboot $STARTUP_SCRIPT_PATH") | crontab -
EOCRON

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

# wait for 1 minute
sleep 300