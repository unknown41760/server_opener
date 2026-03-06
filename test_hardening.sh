#!/bin/bash

# =============================================================================
# Server Hardening Test Suite
# =============================================================================
# Comprehensive tests for server_hardening.sh
# Run this after hardening to verify all security measures are in place
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================
SCRIPT_VERSION="1.0"
NEW_USER="sysadmin"
NEW_SSH_PORT="2202"
REPORT_FILE="/root/hardening-test-report-$(date +%Y%m%d_%H%M%S).txt"
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1" | tee -a "$REPORT_FILE"
}

pass() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$REPORT_FILE"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$REPORT_FILE"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$REPORT_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$REPORT_FILE"
}

section() {
    echo -e "\n${YELLOW}========================================${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${YELLOW}========================================${NC}\n"
    echo -e "\n=== $1 ===" >> "$REPORT_FILE"
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

test_user_creation() {
    section "TEST: User Creation"
    
    # Test 1: User exists
    log_test "Checking if user $NEW_USER exists..."
    if id "$NEW_USER" &>/dev/null; then
        pass "User $NEW_USER exists"
    else
        fail "User $NEW_USER does not exist"
        return 1
    fi
    
    # Test 2: User is in sudo group
    log_test "Checking if user is in sudo group..."
    if groups "$NEW_USER" | grep -q "sudo"; then
        pass "User is in sudo group"
    else
        fail "User is not in sudo group"
    fi
    
    # Test 3: User home directory exists
    log_test "Checking home directory..."
    if [ -d "/home/$NEW_USER" ]; then
        pass "Home directory exists"
    else
        fail "Home directory does not exist"
    fi
    
    # Test 4: .ssh directory exists with correct permissions
    log_test "Checking .ssh directory permissions..."
    SSH_DIR="/home/$NEW_USER/.ssh"
    if [ -d "$SSH_DIR" ]; then
        PERMS=$(stat -c "%a" "$SSH_DIR")
        if [ "$PERMS" = "700" ]; then
            pass ".ssh directory has correct permissions (700)"
        else
            fail ".ssh directory has wrong permissions ($PERMS, expected 700)"
        fi
    else
        fail ".ssh directory does not exist"
    fi
    
    # Test 5: authorized_keys file exists with correct permissions
    log_test "Checking authorized_keys file..."
    AUTH_KEYS="$SSH_DIR/authorized_keys"
    if [ -f "$AUTH_KEYS" ]; then
        PERMS=$(stat -c "%a" "$AUTH_KEYS")
        if [ "$PERMS" = "600" ]; then
            pass "authorized_keys has correct permissions (600)"
        else
            fail "authorized_keys has wrong permissions ($PERMS, expected 600)"
        fi
    else
        fail "authorized_keys file does not exist"
    fi
    
    # Test 6: SSH keys were generated
    log_test "Checking SSH key generation..."
    if ls /root/.ssh/server_hardening_key_* 1>/dev/null 2>&1; then
        pass "SSH key pair exists"
    else
        fail "SSH key pair not found"
    fi
}

test_ssh_configuration() {
    section "TEST: SSH Configuration"
    
    # Test 7: SSH is listening on correct port
    log_test "Checking SSH port..."
    if ss -tlnp | grep -q ":$NEW_SSH_PORT"; then
        pass "SSH is listening on port $NEW_SSH_PORT"
    else
        fail "SSH is not listening on port $NEW_SSH_PORT"
    fi
    
    # Test 8: SSH not listening on port 22
    log_test "Checking port 22 is not used..."
    if ! ss -tlnp | grep -q ":22 "; then
        pass "Port 22 is not listening"
    else
        warn "Port 22 is still listening (may be acceptable)"
    fi
    
    # Test 9: Root login disabled
    log_test "Checking root login is disabled..."
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
        pass "Root login is disabled"
    else
        fail "Root login is not disabled"
    fi
    
    # Test 10: Password authentication disabled
    log_test "Checking password authentication..."
    if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
        pass "Password authentication is disabled"
    else
        fail "Password authentication is still enabled"
    fi
    
    # Test 11: Key authentication enabled
    log_test "Checking public key authentication..."
    if grep -q "^PubkeyAuthentication yes" /etc/ssh/sshd_config; then
        pass "Public key authentication is enabled"
    else
        fail "Public key authentication is not enabled"
    fi
    
    # Test 12: X11 forwarding disabled
    log_test "Checking X11 forwarding..."
    if grep -q "^X11Forwarding no" /etc/ssh/sshd_config; then
        pass "X11 forwarding is disabled"
    else
        fail "X11 forwarding is still enabled"
    fi
    
    # Test 13: AllowUsers directive present
    log_test "Checking AllowUsers directive..."
    if grep -q "^AllowUsers $NEW_USER" /etc/ssh/sshd_config; then
        pass "AllowUsers directive configured for $NEW_USER"
    else
        fail "AllowUsers directive not configured correctly"
    fi
    
    # Test 14: SSH config syntax is valid
    log_test "Validating SSH config syntax..."
    if sshd -t 2>/dev/null; then
        pass "SSH configuration is syntactically valid"
    else
        fail "SSH configuration has syntax errors"
    fi
    
    # Test 15: SSH service is running
    log_test "Checking SSH service status..."
    if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
        pass "SSH service is running"
    else
        fail "SSH service is not running"
    fi
}

test_firewall() {
    section "TEST: Firewall (UFW)"
    
    # Test 16: UFW is installed
    log_test "Checking UFW installation..."
    if command -v ufw &>/dev/null; then
        pass "UFW is installed"
    else
        fail "UFW is not installed"
        return 1
    fi
    
    # Test 17: UFW is active
    log_test "Checking UFW status..."
    if ufw status | grep -q "Status: active"; then
        pass "UFW is active"
    else
        fail "UFW is not active"
    fi
    
    # Test 18: SSH port is allowed
    log_test "Checking SSH port in UFW..."
    if ufw status | grep -q "$NEW_SSH_PORT/tcp"; then
        pass "Port $NEW_SSH_PORT is allowed in UFW"
    else
        fail "Port $NEW_SSH_PORT is not allowed in UFW"
    fi
    
    # Test 19: Default deny incoming
    log_test "Checking default incoming policy..."
    if ufw status verbose | grep -q "Default: deny (incoming)"; then
        pass "Default incoming policy is deny"
    else
        fail "Default incoming policy is not deny"
    fi
    
    # Test 20: Default allow outgoing
    log_test "Checking default outgoing policy..."
    # Check both verbose and numbered output formats
    if ufw status verbose 2>/dev/null | grep -qE "Default:.*allow.*outgoing|Default outgoing policy.*allow"; then
        pass "Default outgoing policy is allow"
    elif ufw status numbered 2>/dev/null | grep -qE "allow.*outgoing|outgoing.*allow"; then
        pass "Default outgoing policy is allow (from numbered status)"
    else
        fail "Default outgoing policy is not allow"
    fi
}

test_fail2ban() {
    section "TEST: Fail2ban"
    
    # Test 21: Fail2ban is installed
    log_test "Checking fail2ban installation..."
    if command -v fail2ban-server &>/dev/null; then
        pass "Fail2ban is installed"
    else
        fail "Fail2ban is not installed"
        return 1
    fi
    
    # Test 22: Fail2ban is running
    log_test "Checking fail2ban service..."
    if systemctl is-active --quiet fail2ban; then
        pass "Fail2ban service is running"
    else
        fail "Fail2ban service is not running"
    fi
    
    # Test 23: Fail2ban is enabled
    log_test "Checking fail2ban auto-start..."
    if systemctl is-enabled --quiet fail2ban 2>/dev/null; then
        pass "Fail2ban is enabled for auto-start"
    else
        fail "Fail2ban is not enabled for auto-start"
    fi
    
    # Test 24: SSH jail is configured
    log_test "Checking SSH jail configuration..."
    if fail2ban-client status sshd &>/dev/null; then
        pass "SSH jail is active"
    else
        fail "SSH jail is not active"
    fi
    
    # Test 25: SSH jail is monitoring correct port
    log_test "Checking jail port configuration..."
    # Try to get port from fail2ban-client (some versions don't support 'get')
    JAIL_PORT=$(fail2ban-client get sshd port 2>/dev/null || echo "")
    
    # If client command doesn't work, check the config file
    if [ -z "$JAIL_PORT" ] || echo "$JAIL_PORT" | grep -q "Invalid command"; then
        # Check jail.local or jail.conf for port setting
        if [ -f /etc/fail2ban/jail.local ]; then
            JAIL_PORT=$(grep -A5 "^\[sshd\]" /etc/fail2ban/jail.local 2>/dev/null | grep "^port" | awk -F'=' '{print $2}' | tr -d ' ')
        fi
        # Fallback to jail.conf
        if [ -z "$JAIL_PORT" ] && [ -f /etc/fail2ban/jail.conf ]; then
            JAIL_PORT=$(grep -A5 "^\[sshd\]" /etc/fail2ban/jail.conf 2>/dev/null | grep "^port" | awk -F'=' '{print $2}' | tr -d ' ')
        fi
    fi
    
    if [ "$JAIL_PORT" = "$NEW_SSH_PORT" ]; then
        pass "Jail is monitoring port $NEW_SSH_PORT"
    elif [ -n "$JAIL_PORT" ]; then
        fail "Jail is monitoring wrong port ($JAIL_PORT, expected $NEW_SSH_PORT)"
    else
        # If we can't determine port, check if jail is at least active
        if fail2ban-client status sshd &>/dev/null; then
            warn "Could not verify jail port via command or config, but jail is active"
        else
            fail "Could not determine jail port and jail may not be active"
        fi
    fi
    
    # Test 26: Reasonable ban settings
    log_test "Checking ban configuration..."
    BANTIME=$(fail2ban-client get sshd bantime 2>/dev/null || echo "0")
    MAXRETRY=$(fail2ban-client get sshd maxretry 2>/dev/null || echo "0")
    
    if [ "$BANTIME" -eq 600 ] && [ "$MAXRETRY" -eq 3 ]; then
        pass "Ban settings are configured correctly (bantime: $BANTIME, maxretry: $MAXRETRY)"
    else
        warn "Ban settings: bantime=$BANTIME, maxretry=$MAXRETRY (expected 600 and 3)"
    fi
}

test_system_hardening() {
    section "TEST: System Hardening"
    
    # Test 27: Logrotate is installed
    log_test "Checking logrotate installation..."
    if command -v logrotate &>/dev/null; then
        pass "Logrotate is installed"
    else
        fail "Logrotate is not installed"
    fi
    
    # Test 28: Unattended-upgrades is installed
    log_test "Checking unattended-upgrades..."
    if dpkg -l | grep -q "unattended-upgrades"; then
        pass "Unattended-upgrades is installed"
    else
        fail "Unattended-upgrades is not installed"
    fi
    
    # Test 29: Automatic updates configured
    log_test "Checking automatic updates configuration..."
    if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
        if grep -q "Unattended-Upgrade" /etc/apt/apt.conf.d/20auto-upgrades || \
           grep -q "APT::Periodic::Unattended-Upgrade" /etc/apt/apt.conf.d/20auto-upgrades; then
            pass "Automatic updates are configured"
        else
            warn "Automatic updates configuration incomplete"
        fi
    else
        fail "Automatic upgrades configuration file not found"
    fi
    
    # Test 30: Secure file permissions on /etc/shadow
    log_test "Checking /etc/shadow permissions..."
    SHADOW_PERMS=$(stat -c "%a" /etc/shadow)
    if [ "$SHADOW_PERMS" = "600" ] || [ "$SHADOW_PERMS" = "640" ]; then
        pass "/etc/shadow has secure permissions ($SHADOW_PERMS)"
    else
        fail "/etc/shadow has insecure permissions ($SHADOW_PERMS)"
    fi
    
    # Test 31: Backup directory exists
    log_test "Checking backup directory..."
    if ls -d /root/.hardening-backup-* 1>/dev/null 2>&1; then
        pass "Backup directory exists"
        BACKUP_DIR=$(ls -d /root/.hardening-backup-* | head -1)
        info "Backup location: $BACKUP_DIR"
    else
        fail "No backup directory found"
    fi
    
    # Test 32: Recovery instructions exist
    log_test "Checking recovery instructions..."
    if [ -f /root/RECOVERY_INSTRUCTIONS.txt ]; then
        pass "Recovery instructions exist"
    else
        fail "Recovery instructions not found"
    fi
}

test_ssh_connectivity() {
    section "TEST: SSH Connectivity (Functional)"
    
    # Test 33: Local SSH connection test
    log_test "Testing local SSH connectivity..."
    
    # Generate a test key if needed
    TEST_KEY="/tmp/test_key_$$"
    ssh-keygen -t ed25519 -f "$TEST_KEY" -N "" -C "test" &>/dev/null
    
    # Add test key to authorized_keys temporarily
    cat "${TEST_KEY}.pub" >> "/home/$NEW_USER/.ssh/authorized_keys"
    
    # Test connection
    if ssh -i "$TEST_KEY" \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=5 \
            -o PasswordAuthentication=no \
            -p "$NEW_SSH_PORT" \
            "$NEW_USER@localhost" \
            "echo 'SSH_TEST_SUCCESS'" 2>/dev/null | grep -q "SSH_TEST_SUCCESS"; then
        pass "SSH key authentication works on port $NEW_SSH_PORT"
    else
        fail "SSH key authentication failed"
    fi
    
    # Cleanup test key
    rm -f "$TEST_KEY" "${TEST_KEY}.pub"
    # Remove test key from authorized_keys
    sed -i '/test$/d' "/home/$NEW_USER/.ssh/authorized_keys"
    
    # Test 34: Root login rejection
    log_test "Testing root login rejection..."
    if ssh -o StrictHostKeyChecking=no \
            -o ConnectTimeout=5 \
            -o PasswordAuthentication=no \
            -p "$NEW_SSH_PORT" \
            "root@localhost" \
            "echo 'test'" 2>/dev/null; then
        fail "Root login is still possible (security risk!)"
    else
        pass "Root login is properly rejected"
    fi
    
    # Test 35: Password authentication rejection
    log_test "Testing password authentication rejection..."
    if ssh -o StrictHostKeyChecking=no \
            -o ConnectTimeout=5 \
            -o PubkeyAuthentication=no \
            -o PasswordAuthentication=yes \
            -p "$NEW_SSH_PORT" \
            "$NEW_USER@localhost" \
            "echo 'test'" 2>/dev/null; then
        fail "Password authentication is still possible (security risk!)"
    else
        pass "Password authentication is properly rejected"
    fi
}

test_security_report() {
    section "TEST: Security Documentation"
    
    # Test 36: Security report exists
    log_test "Checking security report..."
    if ls /root/security-hardening-report-*.txt 1>/dev/null 2>&1; then
        pass "Security report generated"
        REPORT=$(ls /root/security-hardening-report-*.txt | head -1)
        info "Report location: $REPORT"
    else
        fail "Security report not found"
    fi
    
    # Test 37: Log file exists
    log_test "Checking hardening log..."
    if ls /var/log/server-hardening-*.log 1>/dev/null 2>&1; then
        pass "Hardening log exists"
    else
        warn "Hardening log not found in expected location"
    fi
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_integration() {
    section "INTEGRATION TESTS"
    
    info "Running comprehensive integration tests..."
    
    # Test 38: All critical services running
    log_test "Verifying all critical services..."
    SERVICES_OK=true
    
    if ! systemctl is-active --quiet sshd && ! systemctl is-active --quiet ssh; then
        fail "SSH service not running"
        SERVICES_OK=false
    fi
    
    if ! systemctl is-active --quiet fail2ban; then
        fail "Fail2ban not running"
        SERVICES_OK=false
    fi
    
    if [ "$SERVICES_OK" = true ]; then
        pass "All critical services are running"
    fi
    
    # Test 39: No conflicting configurations
    log_test "Checking for configuration conflicts..."
    
    # Check if PermitRootLogin appears multiple times
    ROOT_COUNT=$(grep -c "^PermitRootLogin" /etc/ssh/sshd_config || echo "0")
    if [ "$ROOT_COUNT" -eq 1 ]; then
        pass "No duplicate PermitRootLogin directives"
    else
        warn "Multiple PermitRootLogin directives found ($ROOT_COUNT)"
    fi
    
    # Test 40: Security score calculation
    log_test "Calculating overall security score..."
    
    SCORE=0
    [ $PASSED_TESTS -ge 30 ] && SCORE=$((SCORE + 25))
    [ $PASSED_TESTS -ge 35 ] && SCORE=$((SCORE + 25))
    [ $FAILED_TESTS -eq 0 ] && SCORE=$((SCORE + 25))
    [ $FAILED_TESTS -le 2 ] && SCORE=$((SCORE + 25))
    
    info "Current Security Score: $SCORE/100"
    
    if [ $SCORE -ge 90 ]; then
        pass "Excellent security posture (Score: $SCORE/100)"
    elif [ $SCORE -ge 75 ]; then
        pass "Good security posture (Score: $SCORE/100)"
    elif [ $SCORE -ge 50 ]; then
        warn "Moderate security posture (Score: $SCORE/100)"
    else
        fail "Poor security posture (Score: $SCORE/100)"
    fi
}

# =============================================================================
# FINAL REPORT
# =============================================================================

print_summary() {
    section "TEST SUMMARY"
    
    echo -e "\n${YELLOW}========================================${NC}"
    echo -e "${YELLOW}TEST RESULTS SUMMARY${NC}"
    echo -e "${YELLOW}========================================${NC}\n"
    
    echo -e "Total Tests:  $TOTAL_TESTS"
    echo -e "${GREEN}Passed:       $PASSED_TESTS${NC}"
    echo -e "${RED}Failed:       $FAILED_TESTS${NC}"
    echo -e "Success Rate: $(awk "BEGIN {printf \"%.1f%%\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")\n"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed! Server is properly hardened.${NC}\n"
    elif [ $FAILED_TESTS -le 3 ]; then
        echo -e "${YELLOW}⚠ Most tests passed. Review failed tests above.${NC}\n"
    else
        echo -e "${RED}✗ Multiple tests failed. Hardening may be incomplete.${NC}\n"
    fi
    
    echo "Detailed report saved to: $REPORT_FILE"
    
    # Add summary to report file
    cat >> "$REPORT_FILE" << EOF

========================================
TEST SUMMARY
========================================
Total Tests: $TOTAL_TESTS
Passed: $PASSED_TESTS
Failed: $FAILED_TESTS
Success Rate: $(awk "BEGIN {printf \"%.1f%%\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")

Test completed: $(date)
========================================
EOF
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    clear
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}SERVER HARDENING TEST SUITE v$SCRIPT_VERSION${NC}"
    echo -e "${YELLOW}========================================${NC}\n"
    
    # Initialize report
    echo "Server Hardening Test Report" > "$REPORT_FILE"
    echo "Generated: $(date)" >> "$REPORT_FILE"
    echo "========================================" >> "$REPORT_FILE"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
    
    # Run all test suites
    test_user_creation
    test_ssh_configuration
    test_firewall
    test_fail2ban
    test_system_hardening
    test_ssh_connectivity
    test_security_report
    test_integration
    
    # Print final summary
    print_summary
    
    # Exit with appropriate code
    if [ $FAILED_TESTS -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
