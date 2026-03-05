# Server Hardening Test Guide

## Files Created

1. **server_hardening.sh** - Main hardening script
2. **test_hardening.sh** - Comprehensive test suite (40+ tests)
3. **run_tests.sh** - Automated runner for both scripts

## Quick Start

### Method 1: Run Everything Automatically
```bash
cd /path/to/scripts
chmod +x run_tests.sh
sudo ./run_tests.sh
```

### Method 2: Run Scripts Separately
```bash
# Step 1: Harden the server
chmod +x server_hardening.sh
sudo ./server_hardening.sh

# Step 2: Verify hardening
chmod +x test_hardening.sh
sudo ./test_hardening.sh
```

## Test VM Setup (Suggested)

### Option 1: Local VM (VirtualBox/VMware)
- Ubuntu 24.04 Server ISO
- 2GB RAM, 20GB disk
- Network: Bridged or NAT

### Option 2: Cloud VM (DigitalOcean/AWS/GCP)
- Ubuntu 24.04 LTS image
- Minimum 1GB RAM
- Allow ports 22 (initial) and 2202 (after hardening)

### Option 3: Docker (Limited Testing)
```bash
docker run -it --privileged ubuntu:24.04 bash
# Then copy scripts and run
```

## Pre-Test Checklist

- [ ] Fresh Ubuntu 24.04 server
- [ ] Root or sudo access
- [ ] Stable internet connection
- [ ] At least 1GB free disk space
- [ ] SSH client ready to test connection

## What the Tests Check

### User Creation Tests (6 tests)
- ✓ User exists
- ✓ User in sudo group
- ✓ Home directory created
- ✓ .ssh directory permissions (700)
- ✓ authorized_keys file permissions (600)
- ✓ SSH key pair generated

### SSH Configuration Tests (9 tests)
- ✓ Listening on correct port (2202)
- ✓ Not listening on port 22
- ✓ Root login disabled
- ✓ Password authentication disabled
- ✓ Key authentication enabled
- ✓ X11 forwarding disabled
- ✓ AllowUsers directive configured
- ✓ Config syntax valid
- ✓ Service running

### Firewall Tests (5 tests)
- ✓ UFW installed
- ✓ UFW active
- ✓ SSH port allowed
- ✓ Default deny incoming
- ✓ Default allow outgoing

### Fail2ban Tests (6 tests)
- ✓ Installed
- ✓ Running
- ✓ Enabled for auto-start
- ✓ SSH jail active
- ✓ Monitoring correct port
- ✓ Reasonable ban settings (3 tries, 10 min)

### System Hardening Tests (6 tests)
- ✓ Logrotate installed
- ✓ Unattended-upgrades installed
- ✓ Auto-updates configured
- ✓ Secure /etc/shadow permissions
- ✓ Backup directory exists
- ✓ Recovery instructions exist

### Functional Tests (3 tests)
- ✓ SSH key authentication works
- ✓ Root login rejected
- ✓ Password auth rejected

### Documentation Tests (2 tests)
- ✓ Security report generated
- ✓ Log file exists

### Integration Tests (3 tests)
- ✓ All services running
- ✓ No config conflicts
- ✓ Security score calculation

## Expected Results

**Pass Rate Target:** 100% (40/40 tests)

**Minimum Acceptable:** 37/40 (92.5%)

## Troubleshooting

### Test Failures

#### SSH Connection Tests Failing
```bash
# Check SSH service status
sudo systemctl status sshd

# Check SSH config syntax
sudo sshd -t

# Check listening ports
sudo ss -tlnp | grep ssh
```

#### UFW Blocking Access
```bash
# Check UFW status
sudo ufw status verbose

# Temporarily disable if needed
sudo ufw disable
```

#### Fail2ban Issues
```bash
# Check fail2ban status
sudo fail2ban-client status

# Check SSH jail
sudo fail2ban-client status sshd

# Unban an IP if needed
sudo fail2ban-client set sshd unbanip <IP>
```

### Recovery

If you're locked out:
1. Access server console (physical/IPMI)
2. Follow instructions in `/root/RECOVERY_INSTRUCTIONS.txt`
3. Or restore from backup in `/root/.hardening-backup-*/`

## Test Output Files

After running tests, check:

1. **Test Report:** `/root/hardening-test-report-*.txt`
2. **Security Report:** `/root/security-hardening-report-*.txt`
3. **Recovery Instructions:** `/root/RECOVERY_INSTRUCTIONS.txt`
4. **Hardening Log:** `/var/log/server-hardening-*.log`

## Manual Verification Commands

```bash
# Test SSH connection
ssh -i ~/.ssh/server_hardening_key_* -p 2202 sysadmin@<server-ip>

# Check sudo access
sudo whoami

# Verify root disabled
ssh -p 2202 root@<server-ip>  # Should fail

# Check UFW
sudo ufw status verbose

# Check fail2ban
sudo fail2ban-client status sshd

# Check running services
sudo systemctl status sshd fail2ban

# View recent auth logs
sudo tail -50 /var/log/auth.log
```

## Test Duration

- **Hardening Script:** 2-5 minutes
- **Test Suite:** 1-2 minutes
- **Total:** ~5-7 minutes

## After Testing

1. Review the test report
2. Verify SSH connectivity from your local machine
3. Save the private key securely
4. Import key into Termius/SSH client
5. Destroy test VM if using cloud provider (avoid charges)

## Contact & Support

If tests fail unexpectedly:
1. Check the log files
2. Review test output for specific failures
3. Try manual verification commands
4. Use recovery instructions if locked out
