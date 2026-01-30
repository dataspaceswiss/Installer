#!/bin/bash
set -e


# Get the directory of the current script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR


# Start all docker services
docker compose --file docker-compose.yml --env-file .env up -d