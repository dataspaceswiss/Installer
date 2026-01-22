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

# ========================= INPUTS =========================

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

# Prompt for UID/GID with 1007 as default
read -p "Enter UID/GID for dataspace user (default: 1007): " uid_gid
if [ -z "$uid_gid" ]; then
    uid_gid=1007
fi

# Validate that uid_gid is a number
if ! [[ "$uid_gid" =~ ^[0-9]+$ ]]; then
    echo "Error: UID/GID must be a number"
    exit 1
fi


# ========================= USER CREATION =========================
echo
echo "Creating user..."

# Create the dataspace group with specified GID (ignore if exists)
groupadd -g $uid_gid dataspace 2>/dev/null || true

# Create a new user called dataspace with specified UID and GID
useradd -m -s /bin/bash -u $uid_gid -g $uid_gid dataspace 2>/dev/null || true



# Check if Docker is already installed
if command -v docker &> /dev/null; then
    echo "Docker is already installed. Skipping installation."    
else
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm /tmp/get-docker.sh
fi

# ========================= DOCKER INSTALLATION =========================

# Test if docker is running
if docker ps &> /dev/null; then
    echo "Docker is running."
else
    echo "Starting Docker service..."
    systemctl start docker
    systemctl enable docker
fi

# Add dataspace to docker group
usermod -aG docker dataspace



echo "Setting up DataSpace directory"

# Create DataSpace opt directory
cd /opt/
mkdir -p ./dataspace

# Change ownership of opt/dataspace to dataspace user
chown -R dataspace:dataspace /opt/dataspace



# ------------------------ Execute the rest as dataspace user ------------------------
sudo -u dataspace bash <<EOSU
set -e


cd /opt/dataspace
mkdir -p ./Platform
cd ./Platform

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
wget -q -O ./caddy/Caddyfile https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/Caddyfile
wget -q -O ./caddy/blocked_ips.caddyfile https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/blocked_ips.caddyfile

# Make scripts executable
chmod +x ./startup.sh
chmod +x ./update.sh

# Update Caddyfile content with domain name and admin email
sed -i "s/{domain_name}/$domain_name/g" ./caddy/Caddyfile 2>/dev/null
sed -i "s/{admin_email}/admin@$domain_name/g" ./caddy/Caddyfile 2>/dev/null

# Update .env file content with domain name and admin email
sed -i "s/{domain_name}/$domain_name/g" ./.env 2>/dev/null
sed -i "s/{admin_email}/admin@$domain_name/g" ./.env 2>/dev/null

# Update .env file content with USER_ID and GROUP_ID
sed -i "s/{user_id}/$uid_gid/g" ./.env 2>/dev/null
sed -i "s/{group_id}/$uid_gid/g" ./.env 2>/dev/null

# Save secrets
echo "$github_key" > ./secrets/gh_key.txt
chmod 600 ./secrets/gh_key.txt
echo "$license_key" > ./secrets/license_key
chmod 600 ./secrets/license_key

# Generate additional secrets if they don't exist
generate_secret() {
    local file=$1
    if [ ! -f "$file" ]; then
        echo "Generating $(basename "$file")..."
        LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 > "$file"
        chmod 600 "$file"
    fi
}

generate_secret "./secrets/platform_admin_password"
generate_secret "./secrets/db_password"
generate_secret "./secrets/encryption_key"
generate_secret "./secrets/smtp_server_password"


echo "Files downloaded and configured successfully."

EOSU

echo
echo "=== Installation Complete ==="
echo
echo "Next steps:"
echo "1. Switch to dataspace user: sudo su - dataspace"
echo "2. Navigate to the platform directory: cd /opt/dataspace/Platform"
echo "3. Review and fill in the .env file as needed"
echo "4. Create the necessary secrets in the ./secrets/ directory"
echo "5. Run the update script: ./update.sh"
echo
echo "Note: You may need to log out and back in for Docker permissions to take effect."
echo "Or run: newgrp docker"
echo
