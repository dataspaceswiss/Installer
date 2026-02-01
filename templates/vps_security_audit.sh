#!/bin/bash

#######################################################
# VPS Security Audit Script
# For Ubuntu systems running Docker containers
# Generates a comprehensive security report
#######################################################

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output file
REPORT_FILE="security_audit_report_$(date +%Y%m%d_%H%M%S).txt"

# Function to print section headers
print_header() {
    echo -e "\n${BLUE}========================================${NC}" | tee -a "$REPORT_FILE"
    echo -e "${BLUE}$1${NC}" | tee -a "$REPORT_FILE"
    echo -e "${BLUE}========================================${NC}" | tee -a "$REPORT_FILE"
}

# Function to print findings
print_finding() {
    local severity=$1
    local message=$2
    case $severity in
        "CRITICAL")
            echo -e "${RED}[CRITICAL] $message${NC}" | tee -a "$REPORT_FILE"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING] $message${NC}" | tee -a "$REPORT_FILE"
            ;;
        "OK")
            echo -e "${GREEN}[OK] $message${NC}" | tee -a "$REPORT_FILE"
            ;;
        "INFO")
            echo -e "[INFO] $message" | tee -a "$REPORT_FILE"
            ;;
    esac
}

# Start audit
echo "==================================================" | tee "$REPORT_FILE"
echo "VPS Security Audit Report" | tee -a "$REPORT_FILE"
echo "Generated: $(date)" | tee -a "$REPORT_FILE"
echo "Hostname: $(hostname)" | tee -a "$REPORT_FILE"
echo "==================================================" | tee -a "$REPORT_FILE"

#######################################################
# 1. SYSTEM INFORMATION
#######################################################
print_header "1. SYSTEM INFORMATION"

echo "OS: $(lsb_release -d | cut -f2)" | tee -a "$REPORT_FILE"
echo "Kernel: $(uname -r)" | tee -a "$REPORT_FILE"
echo "Uptime: $(uptime -p)" | tee -a "$REPORT_FILE"
echo "Architecture: $(uname -m)" | tee -a "$REPORT_FILE"

#######################################################
# 2. USER AND ACCESS AUDIT
#######################################################
print_header "2. USER AND ACCESS AUDIT"

# Check for users with UID 0 (root privileges)
echo -e "\nUsers with UID 0 (root privileges):" | tee -a "$REPORT_FILE"
awk -F: '($3 == 0) {print $1}' /etc/passwd | tee -a "$REPORT_FILE"
if [ "$(awk -F: '($3 == 0) {print $1}' /etc/passwd | wc -l)" -gt 1 ]; then
    print_finding "CRITICAL" "Multiple users with UID 0 detected!"
fi

# Check for users with empty passwords
echo -e "\nChecking for users with empty passwords:" | tee -a "$REPORT_FILE"
if sudo awk -F: '($2 == "" ) {print $1}' /etc/shadow 2>/dev/null | grep -q .; then
    print_finding "CRITICAL" "Users with empty passwords found!"
    sudo awk -F: '($2 == "" ) {print $1}' /etc/shadow 2>/dev/null | tee -a "$REPORT_FILE"
else
    print_finding "OK" "No users with empty passwords"
fi

# List all user accounts
echo -e "\nAll user accounts:" | tee -a "$REPORT_FILE"
awk -F: '{if ($3 >= 1000) print $1 " (UID: " $3 ")"}' /etc/passwd | tee -a "$REPORT_FILE"

# Check for users with sudo access
echo -e "\nUsers with sudo access:" | tee -a "$REPORT_FILE"
getent group sudo | cut -d: -f4 | tee -a "$REPORT_FILE"

# Check last logins
echo -e "\nRecent login history (last 10):" | tee -a "$REPORT_FILE"
last -n 10 | tee -a "$REPORT_FILE"

# Check for failed login attempts
echo -e "\nRecent failed login attempts:" | tee -a "$REPORT_FILE"
if [ -f /var/log/auth.log ]; then
    grep "Failed password" /var/log/auth.log | tail -20 | tee -a "$REPORT_FILE"
fi

#######################################################
# 3. SSH CONFIGURATION AUDIT
#######################################################
print_header "3. SSH CONFIGURATION AUDIT"

SSH_CONFIG="/etc/ssh/sshd_config"

if [ -f "$SSH_CONFIG" ]; then
    # Check PermitRootLogin
    echo -e "\nChecking SSH configurations:" | tee -a "$REPORT_FILE"
    
    ROOT_LOGIN=$(grep "^PermitRootLogin" "$SSH_CONFIG" | awk '{print $2}')
    if [ "$ROOT_LOGIN" == "no" ] || [ "$ROOT_LOGIN" == "prohibit-password" ]; then
        print_finding "OK" "Root login properly restricted: $ROOT_LOGIN"
    else
        print_finding "CRITICAL" "Root login not properly restricted! Current: $ROOT_LOGIN"
    fi
    
    # Check PasswordAuthentication
    PASS_AUTH=$(grep "^PasswordAuthentication" "$SSH_CONFIG" | awk '{print $2}')
    if [ "$PASS_AUTH" == "no" ]; then
        print_finding "OK" "Password authentication disabled"
    else
        print_finding "WARNING" "Password authentication enabled - consider using SSH keys only"
    fi
    
    # Check for SSH key authentication
    PUBKEY_AUTH=$(grep "^PubkeyAuthentication" "$SSH_CONFIG" | awk '{print $2}')
    if [ "$PUBKEY_AUTH" == "yes" ]; then
        print_finding "OK" "Public key authentication enabled"
    fi
    
    # Check SSH protocol
    PROTOCOL=$(grep "^Protocol" "$SSH_CONFIG" | awk '{print $2}')
    if [ -z "$PROTOCOL" ] || [ "$PROTOCOL" == "2" ]; then
        print_finding "OK" "Using SSH Protocol 2 (or default)"
    else
        print_finding "WARNING" "Not using SSH Protocol 2"
    fi
    
    # Check SSH port
    SSH_PORT=$(grep "^Port" "$SSH_CONFIG" | awk '{print $2}')
    if [ -z "$SSH_PORT" ]; then
        print_finding "INFO" "SSH running on default port 22 - consider changing to non-standard port"
    else
        print_finding "OK" "SSH running on custom port: $SSH_PORT"
    fi
    
    # Check MaxAuthTries
    MAX_AUTH=$(grep "^MaxAuthTries" "$SSH_CONFIG" | awk '{print $2}')
    if [ -n "$MAX_AUTH" ] && [ "$MAX_AUTH" -le 3 ]; then
        print_finding "OK" "MaxAuthTries set to $MAX_AUTH"
    else
        print_finding "WARNING" "MaxAuthTries not set or too high (current: ${MAX_AUTH:-default})"
    fi
else
    print_finding "WARNING" "SSH config file not found at $SSH_CONFIG"
fi

#######################################################
# 4. FIREWALL CONFIGURATION
#######################################################
print_header "4. FIREWALL CONFIGURATION"

# Check UFW status
if command -v ufw &> /dev/null; then
    echo -e "\nUFW (Uncomplicated Firewall) Status:" | tee -a "$REPORT_FILE"
    sudo ufw status verbose | tee -a "$REPORT_FILE"
    
    if sudo ufw status | grep -q "Status: active"; then
        print_finding "OK" "UFW is active"
    else
        print_finding "CRITICAL" "UFW is not active!"
    fi
else
    print_finding "WARNING" "UFW not installed"
fi

# Check iptables rules
echo -e "\nActive iptables rules:" | tee -a "$REPORT_FILE"
sudo iptables -L -n -v | tee -a "$REPORT_FILE"

#######################################################
# 5. SYSTEM UPDATES AND PATCHES
#######################################################
print_header "5. SYSTEM UPDATES AND PATCHES"

# Check for available updates
echo -e "\nChecking for available updates..." | tee -a "$REPORT_FILE"
sudo apt update &> /dev/null
UPDATES=$(apt list --upgradable 2>/dev/null | grep -c upgradable)

if [ "$UPDATES" -gt 0 ]; then
    print_finding "WARNING" "$UPDATES package updates available"
    apt list --upgradable 2>/dev/null | tee -a "$REPORT_FILE"
else
    print_finding "OK" "System is up to date"
fi

# Check for security updates
echo -e "\nSecurity updates:" | tee -a "$REPORT_FILE"
SEC_UPDATES=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l)
if [ "$SEC_UPDATES" -gt 0 ]; then
    print_finding "CRITICAL" "$SEC_UPDATES security updates available!"
    apt list --upgradable 2>/dev/null | grep -i security | tee -a "$REPORT_FILE"
else
    print_finding "OK" "No pending security updates"
fi

# Check if unattended-upgrades is enabled
if dpkg -l | grep -q unattended-upgrades; then
    print_finding "OK" "unattended-upgrades is installed"
    if systemctl is-enabled unattended-upgrades &>/dev/null; then
        print_finding "OK" "Automatic security updates enabled"
    else
        print_finding "WARNING" "Automatic security updates not enabled"
    fi
else
    print_finding "WARNING" "unattended-upgrades not installed - consider enabling automatic security updates"
fi

#######################################################
# 6. DOCKER SECURITY AUDIT
#######################################################
print_header "6. DOCKER SECURITY AUDIT"

if command -v docker &> /dev/null; then
    echo -e "\nDocker Version:" | tee -a "$REPORT_FILE"
    docker version --format '{{.Server.Version}}' 2>/dev/null | tee -a "$REPORT_FILE"
    
    # Check Docker daemon configuration
    echo -e "\nDocker daemon configuration:" | tee -a "$REPORT_FILE"
    if [ -f /etc/docker/daemon.json ]; then
        cat /etc/docker/daemon.json | tee -a "$REPORT_FILE"
        
        # Check for live-restore
        if grep -q '"live-restore": true' /etc/docker/daemon.json; then
            print_finding "OK" "Docker live-restore enabled"
        else
            print_finding "WARNING" "Docker live-restore not enabled"
        fi
        
        # Check for userns-remap
        if grep -q '"userns-remap"' /etc/docker/daemon.json; then
            print_finding "OK" "User namespace remapping configured"
        else
            print_finding "WARNING" "User namespace remapping not configured"
        fi
    else
        print_finding "WARNING" "/etc/docker/daemon.json not found"
    fi
    
    # List running containers
    echo -e "\nRunning containers:" | tee -a "$REPORT_FILE"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | tee -a "$REPORT_FILE"
    
    # Check for containers running as root
    echo -e "\nChecking container user configurations:" | tee -a "$REPORT_FILE"
    for container in $(docker ps -q); do
        CONTAINER_NAME=$(docker inspect --format='{{.Name}}' "$container" | sed 's/\///')
        CONTAINER_USER=$(docker inspect --format='{{.Config.User}}' "$container")
        
        if [ -z "$CONTAINER_USER" ] || [ "$CONTAINER_USER" == "root" ] || [ "$CONTAINER_USER" == "0" ]; then
            print_finding "WARNING" "Container $CONTAINER_NAME running as root"
        else
            print_finding "OK" "Container $CONTAINER_NAME running as user: $CONTAINER_USER"
        fi
    done
    
    # Check for privileged containers
    echo -e "\nChecking for privileged containers:" | tee -a "$REPORT_FILE"
    for container in $(docker ps -q); do
        CONTAINER_NAME=$(docker inspect --format='{{.Name}}' "$container" | sed 's/\///')
        IS_PRIVILEGED=$(docker inspect --format='{{.HostConfig.Privileged}}' "$container")
        
        if [ "$IS_PRIVILEGED" == "true" ]; then
            print_finding "CRITICAL" "Container $CONTAINER_NAME is running in privileged mode!"
        else
            print_finding "OK" "Container $CONTAINER_NAME not privileged"
        fi
    done
    
    # Check container capabilities
    echo -e "\nChecking container capabilities:" | tee -a "$REPORT_FILE"
    for container in $(docker ps -q); do
        CONTAINER_NAME=$(docker inspect --format='{{.Name}}' "$container" | sed 's/\///')
        CAP_ADD=$(docker inspect --format='{{.HostConfig.CapAdd}}' "$container")
        
        if [ "$CAP_ADD" != "[]" ] && [ "$CAP_ADD" != "<no value>" ]; then
            print_finding "WARNING" "Container $CONTAINER_NAME has added capabilities: $CAP_ADD"
        fi
    done
    
    # Check for exposed ports
    echo -e "\nExposed container ports:" | tee -a "$REPORT_FILE"
    docker ps --format "{{.Names}}: {{.Ports}}" | tee -a "$REPORT_FILE"
    
    # Check Docker socket exposure
    echo -e "\nChecking for Docker socket mounting:" | tee -a "$REPORT_FILE"
    for container in $(docker ps -q); do
        CONTAINER_NAME=$(docker inspect --format='{{.Name}}' "$container" | sed 's/\///')
        SOCKET_MOUNT=$(docker inspect --format='{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' "$container" | grep docker.sock)
        
        if [ -n "$SOCKET_MOUNT" ]; then
            print_finding "CRITICAL" "Container $CONTAINER_NAME has Docker socket mounted - security risk!"
        fi
    done
    
    # Check image vulnerabilities (if docker scan is available)
    echo -e "\nChecking for outdated images:" | tee -a "$REPORT_FILE"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}" | tee -a "$REPORT_FILE"
    
    # Check for Docker Compose
    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        print_finding "INFO" "Docker Compose is installed"
    fi
    
    # Check Docker network configuration
    echo -e "\nDocker networks:" | tee -a "$REPORT_FILE"
    docker network ls | tee -a "$REPORT_FILE"
    
else
    print_finding "WARNING" "Docker not installed or not in PATH"
fi

#######################################################
# 7. NETWORK SECURITY
#######################################################
print_header "7. NETWORK SECURITY"

# Check listening ports
echo -e "\nListening TCP ports:" | tee -a "$REPORT_FILE"
sudo ss -tlnp | tee -a "$REPORT_FILE"

echo -e "\nListening UDP ports:" | tee -a "$REPORT_FILE"
sudo ss -ulnp | tee -a "$REPORT_FILE"

# Check for open ports that shouldn't be
echo -e "\nAnalyzing exposed services:" | tee -a "$REPORT_FILE"
DANGEROUS_PORTS="23 25 110 143 445 3389"
for port in $DANGEROUS_PORTS; do
    if sudo ss -tlnp | grep -q ":$port "; then
        print_finding "WARNING" "Potentially dangerous port $port is listening"
    fi
done

# Check IP forwarding
echo -e "\nIP Forwarding status:" | tee -a "$REPORT_FILE"
IP_FORWARD=$(cat /proc/sys/net/ipv4/ip_forward)
if [ "$IP_FORWARD" == "1" ]; then
    print_finding "INFO" "IP forwarding is enabled (required for Docker)"
else
    print_finding "INFO" "IP forwarding is disabled"
fi

#######################################################
# 8. FILE SYSTEM SECURITY
#######################################################
print_header "8. FILE SYSTEM SECURITY"

# Check world-writable directories
echo -e "\nSearching for world-writable directories (this may take a moment)..." | tee -a "$REPORT_FILE"
WORLD_WRITABLE=$(find / -path /proc -prune -o -path /sys -prune -o -type d -perm -0002 -ls 2>/dev/null | head -20)
if [ -n "$WORLD_WRITABLE" ]; then
    print_finding "WARNING" "World-writable directories found:"
    echo "$WORLD_WRITABLE" | tee -a "$REPORT_FILE"
else
    print_finding "OK" "No suspicious world-writable directories found"
fi

# Check for SUID/SGID files
echo -e "\nSearching for SUID/SGID files..." | tee -a "$REPORT_FILE"
find / -path /proc -prune -o -path /sys -prune -o -type f \( -perm -4000 -o -perm -2000 \) -ls 2>/dev/null | head -30 | tee -a "$REPORT_FILE"

# Check /tmp permissions
echo -e "\n/tmp directory permissions:" | tee -a "$REPORT_FILE"
ls -ld /tmp | tee -a "$REPORT_FILE"
if mount | grep -q "on /tmp.*noexec"; then
    print_finding "OK" "/tmp mounted with noexec"
else
    print_finding "WARNING" "/tmp not mounted with noexec - consider adding this security measure"
fi

#######################################################
# 9. PROCESS AND SERVICE AUDIT
#######################################################
print_header "9. PROCESS AND SERVICE AUDIT"

# Check running services
echo -e "\nEnabled systemd services:" | tee -a "$REPORT_FILE"
systemctl list-unit-files --type=service --state=enabled | tee -a "$REPORT_FILE"

# Check for suspicious processes
echo -e "\nTop CPU consuming processes:" | tee -a "$REPORT_FILE"
ps aux --sort=-%cpu | head -10 | tee -a "$REPORT_FILE"

echo -e "\nTop memory consuming processes:" | tee -a "$REPORT_FILE"
ps aux --sort=-%mem | head -10 | tee -a "$REPORT_FILE"

#######################################################
# 10. LOG FILES AND MONITORING
#######################################################
print_header "10. LOG FILES AND MONITORING"

# Check if fail2ban is installed
if command -v fail2ban-client &> /dev/null; then
    print_finding "OK" "fail2ban is installed"
    echo -e "\nfail2ban status:" | tee -a "$REPORT_FILE"
    sudo fail2ban-client status | tee -a "$REPORT_FILE"
else
    print_finding "WARNING" "fail2ban not installed - consider installing for brute-force protection"
fi

# Check log file sizes
echo -e "\nLog file sizes:" | tee -a "$REPORT_FILE"
du -sh /var/log/* 2>/dev/null | sort -h | tail -10 | tee -a "$REPORT_FILE"

# Check for suspicious cron jobs
echo -e "\nSystem cron jobs:" | tee -a "$REPORT_FILE"
cat /etc/crontab 2>/dev/null | tee -a "$REPORT_FILE"
ls -la /etc/cron.* 2>/dev/null | tee -a "$REPORT_FILE"

#######################################################
# 11. KERNEL AND SYSTEM HARDENING
#######################################################
print_header "11. KERNEL AND SYSTEM HARDENING"

echo -e "\nKernel security parameters:" | tee -a "$REPORT_FILE"

# Check important sysctl settings
SYSCTL_CHECKS=(
    "net.ipv4.conf.all.send_redirects:0"
    "net.ipv4.conf.default.send_redirects:0"
    "net.ipv4.conf.all.accept_redirects:0"
    "net.ipv4.conf.default.accept_redirects:0"
    "net.ipv4.conf.all.secure_redirects:0"
    "net.ipv4.conf.default.secure_redirects:0"
    "net.ipv4.icmp_echo_ignore_broadcasts:1"
    "net.ipv4.tcp_syncookies:1"
)

for check in "${SYSCTL_CHECKS[@]}"; do
    param=$(echo "$check" | cut -d: -f1)
    expected=$(echo "$check" | cut -d: -f2)
    actual=$(sysctl -n "$param" 2>/dev/null)
    
    echo "$param = $actual (expected: $expected)" | tee -a "$REPORT_FILE"
    if [ "$actual" != "$expected" ]; then
        print_finding "WARNING" "$param should be set to $expected"
    fi
done

# Check if AppArmor is enabled
echo -e "\nAppArmor status:" | tee -a "$REPORT_FILE"
if command -v aa-status &> /dev/null; then
    sudo aa-status | tee -a "$REPORT_FILE"
    print_finding "OK" "AppArmor is installed"
else
    print_finding "WARNING" "AppArmor not installed"
fi

#######################################################
# 12. DISK USAGE AND RESOURCE MONITORING
#######################################################
print_header "12. DISK USAGE AND RESOURCE MONITORING"

echo -e "\nDisk usage:" | tee -a "$REPORT_FILE"
df -h | tee -a "$REPORT_FILE"

# Check for nearly full disks
df -h | awk '{print $5 " " $6}' | grep -v "Use%" | while read line; do
    usage=$(echo "$line" | awk '{print $1}' | sed 's/%//')
    mount=$(echo "$line" | awk '{print $2}')
    if [ "$usage" -ge 90 ]; then
        print_finding "CRITICAL" "Disk usage critical on $mount: ${usage}%"
    elif [ "$usage" -ge 80 ]; then
        print_finding "WARNING" "Disk usage high on $mount: ${usage}%"
    fi
done

echo -e "\nMemory usage:" | tee -a "$REPORT_FILE"
free -h | tee -a "$REPORT_FILE"

echo -e "\nLoad average:" | tee -a "$REPORT_FILE"
uptime | tee -a "$REPORT_FILE"

#######################################################
# 13. ADDITIONAL SECURITY TOOLS
#######################################################
print_header "13. ADDITIONAL SECURITY TOOLS CHECK"

# Check for various security tools
SECURITY_TOOLS=(
    "ufw:Firewall"
    "fail2ban:Intrusion prevention"
    "rkhunter:Rootkit detection"
    "chkrootkit:Rootkit detection"
    "lynis:Security auditing"
    "aide:File integrity monitoring"
    "clamav:Antivirus"
)

echo -e "\nSecurity tools installation status:" | tee -a "$REPORT_FILE"
for tool_info in "${SECURITY_TOOLS[@]}"; do
    tool=$(echo "$tool_info" | cut -d: -f1)
    description=$(echo "$tool_info" | cut -d: -f2)
    
    if command -v "$tool" &> /dev/null || dpkg -l | grep -q "^ii  $tool"; then
        print_finding "OK" "$description ($tool) is installed"
    else
        print_finding "INFO" "$description ($tool) not installed - consider installing"
    fi
done

#######################################################
# 14. SUMMARY AND RECOMMENDATIONS
#######################################################
print_header "14. SUMMARY AND RECOMMENDATIONS"

echo -e "\n--- CRITICAL ISSUES ---" | tee -a "$REPORT_FILE"
grep "\[CRITICAL\]" "$REPORT_FILE" | sed 's/\x1b\[[0-9;]*m//g' | tee -a "${REPORT_FILE}.summary"

echo -e "\n--- WARNINGS ---" | tee -a "$REPORT_FILE"
grep "\[WARNING\]" "$REPORT_FILE" | sed 's/\x1b\[[0-9;]*m//g' | tee -a "${REPORT_FILE}.summary"

echo -e "\n--- RECOMMENDATIONS ---" | tee -a "$REPORT_FILE"
cat << 'EOF' | tee -a "$REPORT_FILE"

1. System Hardening:
   - Ensure UFW firewall is enabled and properly configured
   - Enable automatic security updates with unattended-upgrades
   - Configure fail2ban to prevent brute-force attacks
   - Disable root SSH login and enforce SSH key authentication
   - Consider changing SSH to non-standard port

2. Docker Security:
   - Run containers as non-root users where possible
   - Avoid privileged containers unless absolutely necessary
   - Never mount Docker socket in containers
   - Regularly update base images
   - Use Docker secrets for sensitive data
   - Implement resource limits on containers
   - Enable user namespace remapping

3. Access Control:
   - Review user accounts and remove unused accounts
   - Ensure all users have strong passwords
   - Limit sudo access to only necessary users
   - Monitor failed login attempts regularly

4. Monitoring:
   - Set up log monitoring and alerting
   - Monitor disk space usage
   - Review running processes regularly
   - Consider implementing intrusion detection (AIDE, rkhunter)

5. Network Security:
   - Close unnecessary open ports
   - Review and restrict container port exposure
   - Consider using a reverse proxy (nginx/traefik) for web services
   - Implement rate limiting on exposed services

6. Regular Maintenance:
   - Keep system and packages updated
   - Regularly review security logs
   - Backup important data regularly
   - Test disaster recovery procedures
   - Review and update security configurations quarterly

EOF

echo -e "\n==================================================" | tee -a "$REPORT_FILE"
echo "Audit completed: $(date)" | tee -a "$REPORT_FILE"
echo "Full report saved to: $REPORT_FILE" | tee -a "$REPORT_FILE"
echo "Summary saved to: ${REPORT_FILE}.summary" | tee -a "$REPORT_FILE"
echo "==================================================" | tee -a "$REPORT_FILE"

# Display quick stats
CRITICAL_COUNT=$(grep -c "\[CRITICAL\]" "$REPORT_FILE" || echo "0")
WARNING_COUNT=$(grep -c "\[WARNING\]" "$REPORT_FILE" || echo "0")
OK_COUNT=$(grep -c "\[OK\]" "$REPORT_FILE" || echo "0")

echo -e "\n${RED}Critical Issues: $CRITICAL_COUNT${NC}"
echo -e "${YELLOW}Warnings: $WARNING_COUNT${NC}"
echo -e "${GREEN}Passed Checks: $OK_COUNT${NC}"

echo -e "\n${BLUE}Please review the report and address critical issues immediately.${NC}"
echo -e "${BLUE}You can paste the contents of $REPORT_FILE back to Claude for discussion.${NC}"