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
echo
echo "[2/7] Backing up volume..."
rsync -a --delete --info=progress2 -h \
  volume/DataSpace_data/ \
  volume_backup/DataSpace_data/

# Start database
echo
echo "[3/7] Starting Database..."
docker compose --file docker-compose.yml --env-file .env up database -d

# Wait till database is ready
until docker exec DataSpace_database pg_isready -U postgres; do
  sleep 1
done

# Create database backup
echo
echo "[4/7] Backing up database..."
docker compose run --rm pgbackups ./backup.sh

# Install database migrations
echo
echo "[5/7] Installing database migrations..."
docker compose run --rm --entrypoint ./DataSpaceMigration api

# Start all docker services
echo
echo "[6/7] Starting all Docker services..."
./startup.sh

# Clean up unused Docker resources
echo
echo "[7/7] Cleaning up unused Docker resources..."
docker image prune -a -f
docker builder prune -f
docker container prune -f

# Final success message
echo
echo "✅ Upgrade complete!"
