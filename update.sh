#!/bin/bash
set -Eeuo pipefail

# Get the directory of the current script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

key_file="./secrets/gh_key.txt"

# Check if the key file exists
if [[ -f "$key_file" ]]; then
    gh_key="$(<"$key_file")"
else
    echo "Key file $key_file not found."
    exit 1
fi

# Login and pull latest docker images
echo "[1/7] Pulling latest images..."
docker login --username Haeri --password-stdin ghcr.io <<< "$gh_key"
docker compose pull

# Backup volume
printf "\n[2/7] Backing up volume...\n"
rsync -a --delete --info=progress2 -h \
  volume/DataSpace_data/ \
  volume_backup/DataSpace_data/

# Start database
printf "\n[3/7] Starting Database...\n"
docker compose --file docker-compose.yml --env-file .env up database -d
sleep 10

# Create database backup
printf "\n[4/7] Backing up database...\n"
docker exec DataSpace_pgbackups ./backup.sh

# Install database migrations
printf "\n[5/7] Installing database migrations...\n"
docker exec DataSpace_api ./DataSpaceMigration

# Start all docker services
printf "\n[6/7] Starting all Docker services...\n"
./startup.sh

# Clean up unused Docker resources
printf "\n[7/7] Cleaning up unused Docker resources...\n"
docker image prune -a -f
docker builder prune -f
docker container prune -f
