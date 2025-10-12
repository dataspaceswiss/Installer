#!/bin/bash
set -e


# Get the directory of the current script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR


key_file="./secrets/gh_key.txt"

# Check if the key file exists
if [ -f "$key_file" ]; then
    gh_key=$(cat "$key_file")
else
    echo "Key file $key_file not found."
    exit 1
fi

# Login and pull latest docker images
echo "[1/6] Pulling latest images..."
docker login --username Haeri --password-stdin ghcr.io <<< "$gh_key"
docker compose pull

# Backup volume
echo "[2/6] Backing up volume..."
rm -rf volume_backup/*
cp -r volume/DataSpace_data volume_backup/DataSpace_data

# Start all docker services
echo "[3/6] Starting Docker services..."
./startup.sh

# Create Backup
echo "[4/6] Backing up database..."
docker exec DataSpace_pgbackups ./backup.sh

# Install database
echo "[5/6] Installing database migrations..."
docker exec DataSpace_api ./DataSpaceMigration

# Clean up unused Docker resources
echo "[6/6] Cleaning up unused Docker resources..."
docker image prune -a -f
docker builder prune -f
docker volume prune -f
docker container prune -f
