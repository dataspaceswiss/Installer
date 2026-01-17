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

# --- Log previous API and Frontend images ---
if docker compose ps -q DataSpace_api >/dev/null 2>&1; then
    OLD_API_IMAGE=$(docker inspect --format='{{.Config.Image}}' $(docker compose ps -q DataSpace_api))
else
    OLD_API_IMAGE="none"
fi

if docker compose ps -q DataSpace_frontend >/dev/null 2>&1; then
    OLD_FRONTEND_IMAGE=$(docker inspect --format='{{.Config.Image}}' $(docker compose ps -q DataSpace_frontend))
else
    OLD_FRONTEND_IMAGE="none"
fi

# Login and pull latest docker images
echo "[1/7] Pulling latest images..."
docker login --username Haeri --password-stdin ghcr.io <<< "$gh_key"
docker compose pull

# --- Log new API and Frontend images ---
NEW_API_IMAGE=$(docker compose images DataSpace_api --quiet)
NEW_FRONTEND_IMAGE=$(docker compose images DataSpace_frontend --quiet)

# Backup volume
printf "\n[2/7] Backing up volume...\n"
rsync -a --delete --info=progress2 -h \
  volume/DataSpace_data/ \
  volume_backup/DataSpace_data/

# Start database
printf "\n[3/7] Starting Database...\n"
docker compose --file docker-compose.yml --env-file .env up database -d

# Wait till database is ready
until docker exec DataSpace_database pg_isready -U postgres; do
  sleep 1
done

# Create database backup
printf "\n[4/7] Backing up database...\n"
docker compose run --rm DataSpace_pgbackups ./backup.sh

# Install database migrations
printf "\n[5/7] Installing database migrations...\n"
docker compose run --rm DataSpace_api ./DataSpaceMigration

# Start all docker services
printf "\n[6/7] Starting all Docker services...\n"
./startup.sh

# Clean up unused Docker resources
printf "\n[7/7] Cleaning up unused Docker resources...\n"
docker image prune -a -f
docker builder prune -f
docker container prune -f

# Final success message
echo
echo "✅ Upgrade complete!"
echo "API:      $OLD_API_IMAGE → $NEW_API_IMAGE"
echo "Frontend: $OLD_FRONTEND_IMAGE → $NEW_FRONTEND_IMAGE"
