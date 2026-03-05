# Server Hardening Test Guide

## Files Created

1. **server_hardening.sh** - Main hardening script (Dual-Port Safe Mode)
2. **test_hardening.sh** - Comprehensive test suite (40+ tests)
3. **run_tests.sh** - Automated runner for both scripts

## Important: Dual-Port Safe Mode

This script uses **Dual-Port Safe Mode** to prevent SSH lockout:
- **During hardening**: Both port 22 (original) AND port 2202 (new) are active
- **Final phase**: User must confirm port 2202 works before port 22 is removed
- **Result**: Zero risk of lockout during the hardening process

### Key Improvements

✅ **Auto-detects SSH service** - Works with `ssh` (Ubuntu) or `sshd` (other distros)  
✅ **Preserves UFW rules** - Won't overwrite existing firewall configuration  
✅ **Dual-port mode** - Port 22 stays open until you explicitly confirm removal  
✅ **Zero lockout risk** - Test the new port before committing changes  
✅ **Optional finalization** - Skip Phase 8 if not ready, finalize later

## Quick Start

### Method 1: Run Everything Automatically
```bash
cd /path/to/scripts
chmod +x run_tests.sh
sudo ./run_tests.sh
```

### Method 2: Run Scripts Separately (Recommended)
```bash
# Step 1: Harden the server (runs in dual-port mode)
chmod +x server_hardening.sh
sudo ./server_hardening.sh

# During the script:
#   - Phase 1-7: Complete hardening with both ports active
#   - When prompted: Copy the SSH private key to your client
#   - Phase 8: Confirm new port works, then remove port 22

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
- **During hardening**: Both ports 22 and 2202 are open
- **After finalization**: Only port 2202 (port 22 is removed)

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
- [ ] Understanding: Script runs in **dual-port safe mode** (port 22 stays open during hardening)
- [ ] Plan: Test port 2202 **before** finalizing (Phase 8)

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
- ✓ Listening on port 22 (during hardening - removed in Phase 8)
- ✓ Root login disabled
- ✓ Password authentication disabled
- ✓ Key authentication enabled
- ✓ X11 forwarding disabled
- ✓ AllowUsers directive configured
- ✓ Config syntax valid
- ✓ Service running (auto-detects ssh vs sshd)

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

## Script Phases (8 Total)

The hardening script runs in 8 phases:

1. **Pre-Flight Checks** - System validation
2. **User Creation** - Create sysadmin user with SSH key
3. **SSH Hardening** - Configure dual ports (22 + 2202)
4. **Firewall Configuration** - Allow both SSH ports in UFW
5. **Fail2ban Setup** - Configure intrusion detection
6. **System Hardening** - Updates, logrotate, permissions
7. **Verification** - Generate reports and documentation
8. **Finalize Hardening** - **User confirmation required**
   - Tests port 2202 connection
   - Removes port 22 from SSH config
   - Removes port 22 from UFW
   - Restarts SSH with only port 2202

**Note**: Phase 8 requires user confirmation. You can skip it if not ready.

## Expected Results

**Pass Rate Target:** 100% (40/40 tests)

**Minimum Acceptable:** 37/40 (92.5%)

## Troubleshooting

### Test Failures

#### SSH Connection Tests Failing
```bash
# Check SSH service status (script auto-detects service name)
sudo systemctl status ssh
# OR
sudo systemctl status sshd

# Check SSH config syntax
sudo sshd -t

# Check listening ports (both should be active during hardening)
sudo ss -tlnp | grep -E ':(22|2202)'
```

#### UFW Blocking Access
```bash
# Check UFW status (both ports 22 and 2202 should be allowed during hardening)
sudo ufw status verbose

# Check which ports are allowed
sudo ufw status numbered | grep -E '(22|2202)'

# Temporarily disable if needed
sudo ufw disable
```

#### Fail2ban Issues
```bash
# Check fail2ban status
sudo fail2ban-client status

# Check SSH jail (monitors port 2202 after finalization)
sudo fail2ban-client status sshd

# Unban an IP if needed
sudo fail2ban-client set sshd unbanip <IP>
```

### Recovery

**Good News**: Dual-port safe mode makes lockouts very unlikely. Port 22 stays open until you explicitly confirm removal.

If you're locked out (only happens if you finalized Phase 8 and then lost keys):
1. Access server console (physical/IPMI)
2. Follow instructions in `/root/RECOVERY_INSTRUCTIONS.txt`
3. Or restore from backup in `/root/.hardening-backup-*/`
4. To restore port 22 temporarily:
   ```bash
   echo "Port 22" >> /etc/ssh/sshd_config
   sudo systemctl restart ssh
   ```

## Test Output Files

After running tests, check:

1. **Test Report:** `/root/hardening-test-report-*.txt`
2. **Security Report:** `/root/security-hardening-report-*.txt`
3. **Recovery Instructions:** `/root/RECOVERY_INSTRUCTIONS.txt`
4. **Hardening Log:** `/var/log/server-hardening-*.log`

## Manual Verification Commands

### During Hardening (Before Phase 8 Finalization)
```bash
# Test NEW port (2202) - Do this before finalizing!
ssh -i ~/.ssh/server_hardening_key_* -p 2202 sysadmin@<server-ip>

# Verify old port (22) still works (during dual-port mode)
ssh -p 22 <your-current-user>@<server-ip>

# Check both ports are listening
sudo ss -tlnp | grep -E ':(22|2202)'

# Check UFW allows both ports
sudo ufw status | grep -E '(22|2202)/tcp'
```

### After Finalization (Phase 8 Complete)
```bash
# Test SSH on new port ONLY
ssh -i ~/.ssh/server_hardening_key_* -p 2202 sysadmin@<server-ip>

# Verify port 22 is closed
ssh -p 22 <user>@<server-ip>  # Should fail

# Check sudo access
sudo whoami

# Verify root disabled
ssh -p 2202 root@<server-ip>  # Should fail

# Check UFW (only 2202 should be listed)
sudo ufw status verbose

# Check fail2ban (monitors port 2202)
sudo fail2ban-client status sshd

# Check running services (auto-detects service name)
sudo systemctl status ssh fail2ban
# OR
sudo systemctl status sshd fail2ban

# View recent auth logs
sudo tail -50 /var/log/auth.log
```

## Test Duration

- **Hardening Script (Phases 1-7):** 2-5 minutes
- **Phase 8 Finalization:** 1 minute (plus testing time)
- **Test Suite:** 1-2 minutes
- **Total:** ~5-8 minutes

**Note**: Phase 8 requires manual confirmation and testing. You can skip it and return later to finalize.

## After Testing

### Before Finalizing (Phase 8):
1. Test port 2202 from your local machine
2. Save the private key securely
3. Import key into your SSH client (Termius, OpenSSH, etc.)
4. Verify you can connect reliably on port 2202

### During Finalization (Phase 8):
5. Confirm port 2202 works when prompted
6. Script will remove port 22 from SSH and UFW

### After Finalization:
7. Verify port 22 is no longer accessible
8. Test sudo access: `sudo whoami`
9. Review the test report
10. Destroy test VM if using cloud provider (avoid charges)

## Contact & Support

If tests fail unexpectedly:
1. Check the log files
2. Review test output for specific failures
3. Try manual verification commands
4. Use recovery instructions if locked out
