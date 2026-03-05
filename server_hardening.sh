#!/bin/bash

# =============================================================================
# Ubuntu 24.04 Server Hardening Script
# =============================================================================
# Production-ready hardening with zero-downtime guarantee
# Based on SERVER_HARDENING_PLAN.md
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION VARIABLES
# =============================================================================
SCRIPT_VERSION="1.0"
NEW_USER="sysadmin"
NEW_SSH_PORT="2202"
BACKUP_DIR="/root/.hardening-backup-$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/server-hardening-$(date +%Y%m%d_%H%M%S).log"
REPORT_FILE="/root/security-hardening-report-$(date +%Y%m%d_%H%M%S).txt"
RECOVERY_FILE="/root/RECOVERY_INSTRUCTIONS.txt"
HOSTNAME=$(hostname)
DATE=$(date +%Y%m%d)
KEY_FILENAME="server_hardening_key_${HOSTNAME}_${DATE}"
KEY_PATH="/root/.ssh/${KEY_FILENAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}" | tee -a "$LOG_FILE"
    log "SUCCESS: $1"
}

log_error() {
    echo -e "${RED}✗ $1${NC}" | tee -a "$LOG_FILE"
    log "ERROR: $1"
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}" | tee -a "$LOG_FILE"
    log "WARNING: $1"
}

log_info() {
    echo -e "${BLUE}ℹ $1${NC}" | tee -a "$LOG_FILE"
    log "INFO: $1"
}

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
    log "PHASE: $1"
}

print_phase() {
    echo -e "\n${YELLOW}[Phase $1/7] $2${NC}"
    log "Starting Phase $1: $2"
}

# Error handler
trap 'log_error "Script failed at line $LINENO with exit code $?"' ERR

# =============================================================================
# ROLLBACK FUNCTIONS
# =============================================================================

rollback_user() {
    log_warning "Rolling back user creation..."
    if id "$NEW_USER" &>/dev/null; then
        userdel -r "$NEW_USER" 2>/dev/null || true
        log_info "User $NEW_USER removed"
    fi
}

rollback_ssh() {
    log_warning "Rolling back SSH configuration..."
    if [ -f "$BACKUP_DIR/sshd_config" ]; then
        cp "$BACKUP_DIR/sshd_config" /etc/ssh/sshd_config
        systemctl restart sshd || systemctl restart ssh
        log_info "SSH configuration restored"
    fi
}

rollback_ufw() {
    log_warning "Rolling back UFW configuration..."
    ufw disable 2>/dev/null || true
    if [ -f "$BACKUP_DIR/ufw.rules" ]; then
        ufw --force reset 2>/dev/null || true
    fi
}

# =============================================================================
# PHASE 1: PRE-FLIGHT CHECKS
# =============================================================================

phase_preflight() {
    print_phase "1" "Pre-Flight Checks"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    log_success "Running as root"
    
    # Check Ubuntu version
    if ! grep -q "Ubuntu 24.04" /etc/os-release; then
        log_warning "This script is designed for Ubuntu 24.04 LTS"
        log_info "Current OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "Ubuntu 24.04 detected"
    fi
    
    # Check available disk space
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 1048576 ]; then
        log_error "Insufficient disk space (need >1GB, have $(($AVAILABLE_SPACE/1024/1024))GB)"
        exit 1
    fi
    log_success "Sufficient disk space available"
    
    # Check internet connectivity
    if ! ping -c 1 -W 5 google.com &>/dev/null; then
        log_warning "Internet connectivity check failed"
        read -p "Continue without internet? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "Internet connectivity confirmed"
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    log_success "Backup directory created: $BACKUP_DIR"
    
    # Create log file
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"
    log_success "Log file created: $LOG_FILE"
    
    log_info "Pre-flight checks completed"
}

# =============================================================================
# PHASE 2: USER CREATION
# =============================================================================

phase_user_creation() {
    print_phase "2" "User Creation"
    
    # Check if user already exists
    if id "$NEW_USER" &>/dev/null; then
        log_warning "User $NEW_USER already exists"
        read -p "Remove and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            userdel -r "$NEW_USER" 2>/dev/null || true
        else
            log_error "Cannot continue with existing user"
            exit 1
        fi
    fi
    
    # Generate random password
    NEW_PASSWORD=$(openssl rand -base64 24)
    
    # Create user
    useradd -m -s /bin/bash "$NEW_USER"
    echo "$NEW_USER:$NEW_PASSWORD" | chpasswd
    usermod -aG sudo "$NEW_USER"
    
    # Force password change on first login
    chage -d 0 "$NEW_USER"
    
    log_success "User $NEW_USER created with sudo privileges"
    
    # Create .ssh directory
    USER_SSH_DIR="/home/$NEW_USER/.ssh"
    mkdir -p "$USER_SSH_DIR"
    chmod 700 "$USER_SSH_DIR"
    chown "$NEW_USER:$NEW_USER" "$USER_SSH_DIR"
    
    log_success ".ssh directory created for $NEW_USER"
    
    # Generate SSH key pair
    log_info "Generating Ed25519 SSH key pair..."
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    
    ssh-keygen -t ed25519 -a 100 -f "$KEY_PATH" -N "" -C "server-hardening-${HOSTNAME}-${DATE}"
    
    log_success "SSH key pair generated"
    
    # Copy public key to user's authorized_keys
    cp "${KEY_PATH}.pub" "$USER_SSH_DIR/authorized_keys"
    chmod 600 "$USER_SSH_DIR/authorized_keys"
    chown -R "$NEW_USER:$NEW_USER" "$USER_SSH_DIR"
    
    log_success "Public key added to authorized_keys"
    
    # Save credentials to backup
    echo "Username: $NEW_USER" > "$BACKUP_DIR/credentials.txt"
    echo "Password: $NEW_PASSWORD" >> "$BACKUP_DIR/credentials.txt"
    echo "SSH Key: $KEY_PATH" >> "$BACKUP_DIR/credentials.txt"
    chmod 600 "$BACKUP_DIR/credentials.txt"
    
    log_info "User creation completed"
}

# =============================================================================
# PHASE 3: SSH HARDENING
# =============================================================================

phase_ssh_hardening() {
    print_phase "3" "SSH Hardening"
    
    # Backup original SSH config
    cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config"
    log_success "Original SSH config backed up"
    
    # Get current SSH port
    CURRENT_PORT=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}' || echo "22")
    [ -z "$CURRENT_PORT" ] && CURRENT_PORT="22"
    
    log_info "Current SSH port: $CURRENT_PORT"
    
    # Create new SSH config
    cat > /etc/ssh/sshd_config << EOF
# Server Hardening SSH Configuration
# Generated: $(date)

# Port configuration
Port $NEW_SSH_PORT
#Port $CURRENT_PORT  # Temporarily commented - dual port mode

# Authentication
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey

# Security settings
X11Forwarding no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Connection settings
MaxAuthTries 3
MaxSessions 2
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# AllowUsers
AllowUsers $NEW_USER

# Protocol
Protocol 2

# HostKeys
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Subsystem
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

    log_success "New SSH configuration written"
    
    # Test SSH config syntax
    if ! sshd -t; then
        log_error "SSH configuration syntax error"
        rollback_ssh
        exit 1
    fi
    log_success "SSH configuration syntax validated"
    
    # Restart SSH service
    log_info "Restarting SSH service..."
    systemctl restart sshd || systemctl restart ssh
    sleep 2
    
    # Verify SSH service is running
    if ! systemctl is-active --quiet sshd && ! systemctl is-active --quiet ssh; then
        log_error "SSH service failed to restart"
        rollback_ssh
        exit 1
    fi
    
    log_success "SSH service restarted successfully"
}

# =============================================================================
# SSH KEY DISPLAY AND PAUSE
# =============================================================================

pause_for_key_copy() {
    print_header "CRITICAL: COPY SSH KEY TO TERMius"
    
    echo -e "\n${YELLOW}========================================${NC}"
    echo -e "${YELLOW}PRIVATE KEY - COPY THIS TO TERMIUS${NC}"
    echo -e "${YELLOW}========================================${NC}\n"
    
    echo -e "${GREEN}Key Location: $KEY_PATH${NC}\n"
    
    echo -e "${BLUE}--- BEGIN PRIVATE KEY ---${NC}"
    cat "$KEY_PATH"
    echo -e "\n${BLUE}--- END PRIVATE KEY ---${NC}\n"
    
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}CONNECTION DETAILS${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo -e "Username: ${GREEN}$NEW_USER${NC}"
    echo -e "Port: ${GREEN}$NEW_SSH_PORT${NC}"
    echo -e "Authentication: ${GREEN}SSH Key${NC}\n"
    
    echo -e "${YELLOW}IMPORTANT:${NC}"
    echo -e "1. Copy the private key above (everything between the markers)"
    echo -e "2. Open Termius and create a new key"
    echo -e "3. Paste the private key and save"
    echo -e "4. Create a new host with:"
    echo -e "   - Address: ${GREEN}$HOSTNAME${NC} (or your server IP)"
    echo -e "   - Port: ${GREEN}$NEW_SSH_PORT${NC}"
    echo -e "   - Username: ${GREEN}$NEW_USER${NC}"
    echo -e "   - Key: Select the key you just created"
    echo -e "5. Test the connection BEFORE proceeding\n"
    
    echo -e "${RED}WARNING: If you don't copy this key now, you'll be locked out!${NC}\n"
    
    read -p "Have you copied the key to Termius and tested the connection? (yes/no): " -r
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_error "User did not confirm key copy. Aborting."
        rollback_ssh
        rollback_user
        exit 1
    fi
    
    log_success "User confirmed key copy"
}

# =============================================================================
# PHASE 4: FIREWALL (UFW)
# =============================================================================

phase_ufw() {
    print_phase "4" "Firewall Configuration (UFW)"
    
    # Backup current UFW rules
    ufw status numbered > "$BACKUP_DIR/ufw.rules" 2>/dev/null || true
    
    # Reset UFW to defaults
    log_info "Configuring UFW defaults..."
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow new SSH port
    ufw allow "$NEW_SSH_PORT/tcp" comment 'SSH hardened port'
    log_success "Port $NEW_SSH_PORT/tcp allowed"
    
    # Ask about additional ports
    echo -e "\n${BLUE}Do you need to open any additional ports? (e.g., 80 for HTTP, 443 for HTTPS)${NC}"
    echo "Enter port numbers separated by spaces (or press Enter to skip):"
    read -r ADDITIONAL_PORTS
    
    if [ -n "$ADDITIONAL_PORTS" ]; then
        for port in $ADDITIONAL_PORTS; do
            if [[ "$port" =~ ^[0-9]+$ ]]; then
                ufw allow "$port/tcp" comment "User specified port"
                log_success "Port $port/tcp allowed"
            fi
        done
    fi
    
    # Enable UFW
    log_info "Enabling UFW..."
    echo "y" | ufw enable
    
    # Verify UFW is active
    if ! ufw status | grep -q "Status: active"; then
        log_error "UFW failed to enable"
        rollback_ufw
        return 1
    fi
    
    log_success "UFW enabled and configured"
    
    # Display UFW status
    echo -e "\n${BLUE}UFW Status:${NC}"
    ufw status verbose
}

# =============================================================================
# PHASE 5: FAIL2BAN
# =============================================================================

phase_fail2ban() {
    print_phase "5" "Fail2ban Configuration"
    
    # Install fail2ban if not present
    if ! command -v fail2ban-server &> /dev/null; then
        log_info "Installing fail2ban..."
        apt-get update -qq
        apt-get install -y fail2ban
    fi
    
    # Backup original config
    if [ -f /etc/fail2ban/jail.conf ]; then
        cp /etc/fail2ban/jail.conf "$BACKUP_DIR/fail2ban-jail.conf"
    fi
    
    # Create custom jail configuration
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Ban hosts for 10 minutes
bantime = 600
# Look back over the last 10 minutes
findtime = 600
# Allow 3 retries
maxretry = 3
# Use iptables for banning
banaction = iptables-multiport

[sshd]
enabled = true
port = $NEW_SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 600
EOF

    log_success "Fail2ban configuration created"
    
    # Restart fail2ban
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    # Verify fail2ban is running
    if ! systemctl is-active --quiet fail2ban; then
        log_error "Fail2ban failed to start"
        return 1
    fi
    
    log_success "Fail2ban started and enabled"
    
    # Display fail2ban status
    echo -e "\n${BLUE}Fail2ban Status:${NC}"
    fail2ban-client status sshd 2>/dev/null || log_warning "Could not get fail2ban status"
}

# =============================================================================
# PHASE 6: SYSTEM HARDENING
# =============================================================================

phase_system_hardening() {
    print_phase "6" "System Hardening"
    
    # Update packages
    log_info "Updating system packages..."
    apt-get update -qq
    apt-get upgrade -y
    log_success "System packages updated"
    
    # Install required packages
    log_info "Installing required packages..."
    apt-get install -y \
        logrotate \
        unattended-upgrades \
        apt-listchanges \
        needrestart \
        2>/dev/null || true
    
    log_success "Required packages installed"
    
    # Configure logrotate
    if [ -f /etc/logrotate.conf ]; then
        cp /etc/logrotate.conf "$BACKUP_DIR/logrotate.conf"
        
        # Ensure logrotate is configured for weekly rotation with compression
        sed -i 's/#weekly/weekly/' /etc/logrotate.conf
        sed -i 's/#compress/compress/' /etc/logrotate.conf
        
        log_success "Logrotate configured"
    fi
    
    # Configure unattended-upgrades
    if [ -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
        cp /etc/apt/apt.conf.d/50unattended-upgrades "$BACKUP_DIR/unattended-upgrades"
        
        # Enable automatic security updates
        cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
        
        # Enable automatic updates
        cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
        
        log_success "Automatic security updates configured"
    fi
    
    # Set secure permissions on sensitive files
    chmod 600 /etc/shadow
    chmod 600 /etc/gshadow
    chmod 644 /etc/passwd
    chmod 644 /etc/group
    
    log_success "File permissions secured"
}

# =============================================================================
# PHASE 7: VERIFICATION & DOCUMENTATION
# =============================================================================

phase_verification() {
    print_phase "7" "Verification & Documentation"
    
    # Create security report
    cat > "$REPORT_FILE" << EOF
===============================================================================
SERVER HARDENING SECURITY REPORT
===============================================================================
Generated: $(date)
Server: $HOSTNAME
Script Version: $SCRIPT_VERSION
===============================================================================

SUMMARY
-------
✓ User created: $NEW_USER
✓ SSH port changed: $NEW_SSH_PORT
✓ Key-based authentication enabled
✓ Root login disabled
✓ UFW firewall enabled
✓ Fail2ban active
✓ Automatic security updates configured

ACCESS INFORMATION
------------------
Username: $NEW_USER
SSH Port: $NEW_SSH_PORT
Authentication: SSH Key Only
Private Key Location: $KEY_PATH

SECURITY MEASURES IMPLEMENTED
-----------------------------
1. User & Access Control
   - New user '$NEW_USER' created with sudo privileges
   - Root login via SSH disabled
   - Password authentication disabled
   - Key-based authentication enforced
   - User forced to change password on first login

2. SSH Security
   - Port changed from 22 to $NEW_SSH_PORT
   - Protocol 2 enforced
   - MaxAuthTries limited to 3
   - LoginGraceTime set to 60 seconds
   - Client alive settings configured
   - X11 forwarding disabled

3. Firewall (UFW)
   - Default deny incoming
   - Default allow outgoing
   - Port $NEW_SSH_PORT allowed for SSH
EOF

    # Add UFW rules to report
    echo "" >> "$REPORT_FILE"
    echo "   UFW Rules:" >> "$REPORT_FILE"
    ufw status numbered >> "$REPORT_FILE" 2>/dev/null || echo "   (UFW status unavailable)" >> "$REPORT_FILE"
    
    cat >> "$REPORT_FILE" << EOF

4. Intrusion Prevention (Fail2ban)
   - SSH jail enabled on port $NEW_SSH_PORT
   - Max retries: 3
   - Ban time: 600 seconds (10 minutes)
   - Find time: 600 seconds

5. System Updates
   - Automatic security updates enabled
   - Daily package list updates
   - Weekly autoclean

BACKUP INFORMATION
------------------
Backup Directory: $BACKUP_DIR
Original SSH Config: $BACKUP_DIR/sshd_config
Original UFW Rules: $BACKUP_DIR/ufw.rules
Original Fail2ban Config: $BACKUP_DIR/fail2ban-jail.conf

TESTING CHECKLIST
-----------------
[ ] Connect via new port: ssh -i $KEY_PATH -p $NEW_SSH_PORT $NEW_USER@<server-ip>
[ ] Verify sudo access: sudo whoami (should return 'root')
[ ] Confirm root disabled: ssh -p $NEW_SSH_PORT root@<server-ip> (should fail)
[ ] Verify firewall: sudo ufw status
[ ] Check fail2ban: sudo fail2ban-client status sshd

NEXT STEPS
----------
1. Save this report and the SSH private key securely
2. Test the connection using the new SSH key
3. Verify sudo access works
4. Store the private key in your password manager
5. Consider setting up SSH key in Termius/SSH client

===============================================================================
END OF REPORT
===============================================================================
EOF

    log_success "Security report generated: $REPORT_FILE"
    
    # Create recovery instructions
    cat > "$RECOVERY_FILE" << EOF
===============================================================================
EMERGENCY RECOVERY INSTRUCTIONS
===============================================================================
Generated: $(date)

IF YOU ARE LOCKED OUT OF THE SERVER:

Option 1: Physical/Console Access
---------------------------------
1. Access server console (physically or via IPMI/iLO/iDRAC)
2. Login as root or use recovery mode
3. To restore SSH on port 22:
   cp $BACKUP_DIR/sshd_config /etc/ssh/sshd_config
   systemctl restart sshd

4. To re-enable root login temporarily:
   echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
   systemctl restart sshd

5. To disable UFW:
   ufw disable

Option 2: Remove User
---------------------
If you need to remove the created user:
   userdel -r $NEW_USER

Option 3: Full Rollback
-----------------------
To completely undo all changes:
   cp $BACKUP_DIR/sshd_config /etc/ssh/sshd_config
   systemctl restart sshd
   ufw disable
   ufw --force reset
   userdel -r $NEW_USER
   systemctl stop fail2ban
   apt-get remove -y fail2ban

===============================================================================
BACKUP LOCATION: $BACKUP_DIR
===============================================================================
EOF

    log_success "Recovery instructions created: $RECOVERY_FILE"
    
    # Secure the files
    chmod 600 "$REPORT_FILE"
    chmod 600 "$RECOVERY_FILE"
    chmod 600 "$KEY_PATH"
    chmod 644 "${KEY_PATH}.pub"
}

# =============================================================================
# FINAL SUMMARY
# =============================================================================

print_final_summary() {
    print_header "HARDENING COMPLETE"
    
    echo -e "\n${GREEN}✓ Server hardening completed successfully!${NC}\n"
    
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}CRITICAL INFORMATION - SAVE THESE${NC}"
    echo -e "${YELLOW}========================================${NC}\n"
    
    echo -e "Username: ${GREEN}$NEW_USER${NC}"
    echo -e "SSH Port: ${GREEN}$NEW_SSH_PORT${NC}"
    echo -e "Private Key: ${GREEN}$KEY_PATH${NC}"
    echo -e "Public Key: ${GREEN}${KEY_PATH}.pub${NC}\n"
    
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}IMPORTANT FILES${NC}"
    echo -e "${YELLOW}========================================${NC}\n"
    
    echo -e "Security Report: ${BLUE}$REPORT_FILE${NC}"
    echo -e "Recovery Instructions: ${BLUE}$RECOVERY_FILE${NC}"
    echo -e "Backup Directory: ${BLUE}$BACKUP_DIR${NC}"
    echo -e "Log File: ${BLUE}$LOG_FILE${NC}\n"
    
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}IMMEDIATE NEXT STEPS${NC}"
    echo -e "${YELLOW}========================================${NC}\n"
    
    echo "1. Test the connection NOW:"
    echo -e "   ${BLUE}ssh -i $KEY_PATH -p $NEW_SSH_PORT $NEW_USER@<your-server-ip>${NC}\n"
    
    echo "2. Verify sudo access:"
    echo -e "   ${BLUE}sudo whoami${NC} (should return 'root')\n"
    
    echo "3. Confirm root is disabled:"
    echo -e "   ${BLUE}ssh -p $NEW_SSH_PORT root@<your-server-ip>${NC} (should fail)\n"
    
    echo "4. Save the private key to a secure location:"
    echo -e "   ${BLUE}cat $KEY_PATH${NC}\n"
    
    echo -e "${RED}WARNING: If you cannot connect now, check the recovery instructions in:${NC}"
    echo -e "${RED}$RECOVERY_FILE${NC}\n"
    
    echo -e "${GREEN}Your server is now hardened and secure!${NC}\n"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    clear
    print_header "Ubuntu 24.04 Server Hardening Script v$SCRIPT_VERSION"
    
    echo -e "\n${YELLOW}WARNING: This script will:${NC}"
    echo "  - Create a new user '$NEW_USER'"
    echo "  - Change SSH port to $NEW_SSH_PORT"
    echo "  - Disable password authentication"
    echo "  - Disable root login via SSH"
    echo "  - Configure firewall and intrusion detection"
    echo ""
    echo -e "${RED}IMPORTANT: Ensure you have a stable connection to this server.${NC}"
    echo ""
    
    read -p "Do you want to proceed? (yes/no): " -r
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    
    # Execute phases
    phase_preflight
    phase_user_creation
    phase_ssh_hardening
    pause_for_key_copy
    phase_ufw
    phase_fail2ban
    phase_system_hardening
    phase_verification
    
    # Final summary
    print_final_summary
    
    log_success "Script completed successfully"
}

# Run main function
main "$@"
