#!/bin/bash
set -e

# Script to test the installer in a Docker container

echo "Building Docker image for testing..."
docker build -t installer-test .

echo "Running installer test in Docker container..."
docker run --rm -e TEST_MODE=true installer-test bash -c '
    # Run the installer
    /tmp/install/install.sh
    
    echo
    echo "=== Validating Installation ==="
    echo

    FAILED=0

    check_dir() {
        if [ -d "$1" ]; then
            echo "✅ Directory exists: $1"
        else
            echo "❌ Directory missing: $1"
            FAILED=1
        fi
    }

    check_file() {
        if [ -f "$1" ]; then
            echo "✅ File exists: $1"
        else
            echo "❌ File missing: $1"
            FAILED=1
        fi
    }

    check_executable() {
        if [ -x "$1" ]; then
            echo "✅ Executable exists: $1"
        else
            echo "❌ Executable missing or not executable: $1"
            FAILED=1
        fi
    }

    # Check directories
    echo "--- Checking directories ---"
    check_dir "/opt/dataspace"
    check_dir "/opt/dataspace/Platform"
    check_dir "/opt/dataspace/Platform/volume"
    check_dir "/opt/dataspace/Platform/volume/DataSpace_data"
    check_dir "/opt/dataspace/Platform/volume/DataSpace_db_data"
    check_dir "/opt/dataspace/Platform/volume/DataSpace_db_backup"
    check_dir "/opt/dataspace/Platform/volume_backup"
    check_dir "/opt/dataspace/Platform/caddy"
    check_dir "/opt/dataspace/Platform/secrets"
    check_dir "/opt/dataspace/Platform/metrics"
    check_dir "/opt/dataspace/Platform/metrics/host_metrics"
    check_dir "/opt/dataspace/Platform/metrics/venv"

    # Check configuration files
    echo
    echo "--- Checking configuration files ---"
    check_file "/opt/dataspace/Platform/docker-compose.yml"
    check_file "/opt/dataspace/Platform/.env"
    check_file "/opt/dataspace/Platform/caddy/Caddyfile"
    check_file "/opt/dataspace/Platform/caddy/blocked_ips.caddyfile"
    check_file "/opt/dataspace/Platform/metrics/metrics_collector.py"

    # Check executable scripts
    echo
    echo "--- Checking executable scripts ---"
    check_executable "/opt/dataspace/Platform/startup.sh"
    check_executable "/opt/dataspace/Platform/update.sh"

    # Check secrets
    echo
    echo "--- Checking secrets ---"
    check_file "/opt/dataspace/Platform/secrets/gh_key.txt"
    check_file "/opt/dataspace/Platform/secrets/license_key"
    check_file "/opt/dataspace/Platform/secrets/platform_admin_password"
    check_file "/opt/dataspace/Platform/secrets/db_password"
    check_file "/opt/dataspace/Platform/secrets/encryption_key"
    check_file "/opt/dataspace/Platform/secrets/smtp_server_password"

    # Check systemd service file
    echo
    echo "--- Checking systemd service ---"
    check_file "/etc/systemd/system/metrics_collector.service"

    # Validate .env file has placeholders replaced
    echo
    echo "--- Checking placeholder replacements ---"
    if grep -q "{domain_name}" /opt/dataspace/Platform/.env; then
        echo "❌ .env still contains {domain_name} placeholder"
        FAILED=1
    else
        echo "✅ .env placeholders replaced"
    fi

    if grep -q "{domain_name}" /opt/dataspace/Platform/caddy/Caddyfile; then
        echo "❌ Caddyfile still contains {domain_name} placeholder"
        FAILED=1
    else
        echo "✅ Caddyfile placeholders replaced"
    fi

    echo
    if [ $FAILED -eq 0 ]; then
        echo "=== ✅ All validation checks passed! ==="
    else
        echo "=== ❌ Some validation checks failed! ==="
        exit 1
    fi
'

echo
echo "✅ Docker test completed successfully!"