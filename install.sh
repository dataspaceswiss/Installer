#!/bin/bash
set -e


# Promt for domain name
read -p "Enter the domain name: " domain_name
# Prompt for admin email
read -p "Enter the admin email: " admin_email
# Prompt for Github key
read -p "Enter the Github key: " github_key


# Create a new user called dataspace_app UID and GID 1002 and add to sudo
useradd -m -s /bin/bash -u 1002 -o -g 1002 dataspace_app
usermod -aG sudo dataspace_app

# propt to set a password for dataspace_app
read -p "Enter the password for dataspace_app: " password
echo "dataspace_app:$password" | chpasswd

# Switch to dataspace_app
su - dataspace_app
cd ~

# Create a new directory for DataSpace
mkdir -p ./DataSpace
cd ./DataSpace

# install docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh ./get-docker.sh

# add dataspace_app to docker group
usermod -aG docker dataspace_app

# Test if docker is running
docker ps

# Remove get-docker.sh
rm ./get-docker.sh

# Make other scripts executable 
chmod +x ./startup.sh
chmod +x ./update.sh

# Create folders
mkdir -p ./volume/
mkdir -p ./volume_backup/
mkdir -p ./caddy/
mkdir -p ./secrets/

# Download resource files
wget https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/startup.sh
wget https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/update.sh
wget https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/docker-compose.yml
wget https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/.env
wget https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/Caddyfile -O ./caddy/Caddyfile
wget https://raw.githubusercontent.com/dataspaceswiss/Installer/refs/heads/main/blocked_ips.caddyfile -O ./caddy/blocked_ips.caddyfile


# Update caddyfile content with domain name and admin email
sed -i "s/${domain_name}/$domain_name/g" ./caddy/Caddyfile
sed -i "s/${admin_email}/$admin_email/g" ./caddy/Caddyfile

# Update .env file content with domain name and admin email
sed -i "s/${domain_name}/$domain_name/g" ./.env
sed -i "s/${admin_email}/$admin_email/g" ./.env

# Save the key to a file
echo $github_key > ./secrets/gh_key.txt

# Register startup script to execute on startup
STARTUP_SCRIPT_PATH=$(realpath "./startup.sh")
(crontab -l ; echo "@reboot $STARTUP_SCRIPT_PATH") | crontab -

# inal step
echo "ill in the .env ile and run ./upate.sh"

# Run updater
# ./update.sh