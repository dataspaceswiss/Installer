#!/bin/bash

# Script to test the installer in a Docker container

echo "Building Docker image for testing..."
docker build -t installer-test .

echo "Running installer test in Docker container..."
docker run --rm -it -e TEST_MODE=true installer-test
