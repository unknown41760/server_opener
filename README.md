# Server Hardening & Automation Scripts

A collection of production-ready bash scripts for server hardening and automation, designed for Ubuntu 24.04 LTS servers with zero-downtime guarantees.

## Scripts

### 1. Server Hardening (`server_hardening.sh`)
Production-ready server hardening script implementing industry best practices with comprehensive safety mechanisms.

**Features:**
- Creates secure admin user (`sysadmin`)
- Generates Ed25519 SSH key pair
- **Configurable SSH port** - user can specify any port (default: 2202)
- **Displays password** alongside SSH key for emergency access
- **Dual-port safe mode** - keeps port 22 open during hardening
- **Auto-detects Ubuntu 24.04 socket activation** and handles it correctly
- Disables root login & password authentication
- Configures UFW firewall
- Sets up Fail2ban intrusion prevention
- Enables automatic security updates
- Full rollback capability
- Interactive pause to copy SSH key to Termius
- 8-phase execution with verification at each step

**Usage:**
```bash
sudo ./server_hardening.sh
```

**Safety Features:**
- Pre-flight environment checks
- Configuration backups before changes
- Syntax validation before applying
- Interactive confirmation before critical steps
- Automatic rollback on failure
- Recovery instructions generated

### 2. Test Suite (`test_hardening.sh`)
Comprehensive test suite with 40+ automated tests to verify all hardening measures.

**Tests Include:**
- User creation & permissions
- SSH configuration (port, auth, security settings)
- Firewall rules & policies
- Fail2ban setup & configuration
- System hardening (updates, permissions)
- **Functional tests** (actual SSH connections)
- Integration tests & security scoring

**Usage:**
```bash
sudo ./test_hardening.sh
```

### 3. Automated Test Runner (`run_tests.sh`)
Runs both hardening script and test suite in sequence.

**Usage:**
```bash
sudo ./run_tests.sh
```

### 4. Vaultwarden LXC Setup (`opener_vaultwarden_lxc.sh`)
Automated setup script for Vaultwarden password manager in LXC containers.

**Usage:**
```bash
./opener_vaultwarden_lxc.sh
```

## Quick Start

### Option 1: Clone & Run
```bash
# Install prerequisites and clone repository
apt update && apt install -y git curl systemd && \
git clone https://github.com/unknown41760/server_opener.git && \
cd server_opener && \
chmod +x *.sh

# Run hardening
sudo ./server_hardening.sh

# Or run everything (hardening + tests)
sudo ./run_tests.sh
```

### Option 2: Direct Install (Vaultwarden only)
```bash
apt update && apt install -y git curl systemd && \
rm -rf ~/server_opener && \
git clone https://github.com/unknown41760/server_opener.git && \
cd server_opener && \
chmod +x opener_vaultwarden_lxc.sh && \
./opener_vaultwarden_lxc.sh
```

## Requirements

- **OS:** Ubuntu 24.04 LTS (primary target)
- **Privileges:** Root access required
- **Network:** Internet connection for package installation
- **Disk:** Minimum 1GB free space
- **Memory:** 512MB minimum, 1GB recommended

## Documentation

- `SERVER_HARDENING_PLAN.md` - Detailed implementation plan
- `TEST_GUIDE.md` - Complete testing documentation
- `README.md` - This file

## Security Features

- **Zero-lockout guarantee** - Tests SSH connectivity before committing changes
- **Atomic operations** - Changes grouped with rollback capability
- **Configuration backups** - Original configs preserved
- **Connection testing** - Verifies access on new port before disabling old
- **Emergency recovery** - Detailed rollback instructions generated
- **Grace period** - Interactive pause to copy SSH keys

## Testing

### Manual Testing
```bash
# Test SSH connection
ssh -i ~/.ssh/server_hardening_key_* -p 2202 sysadmin@<server-ip>

# Verify sudo access
sudo whoami

# Confirm root disabled
ssh -p 2202 root@<server-ip>  # Should fail

# Check services
sudo ufw status verbose
sudo fail2ban-client status sshd
```

### Automated Testing
```bash
sudo ./test_hardening.sh
```

**Expected Results:** 100% pass rate (40/40 tests)

## Output Files

After running scripts, check these locations:

- `/root/security-hardening-report-*.txt` - Security configuration report
- `/root/hardening-test-report-*.txt` - Test results
- `/root/RECOVERY_INSTRUCTIONS.txt` - Emergency rollback guide
- `/var/log/server-hardening-*.log` - Detailed execution log
- `/root/.hardening-backup-*/` - Configuration backups

## Recovery

If you get locked out:

1. Access server console (physical/IPMI)
2. Follow `/root/RECOVERY_INSTRUCTIONS.txt`
3. Or restore from `/root/.hardening-backup-*/`

**Quick recovery:**
```bash
# Restore SSH config
cp /root/.hardening-backup-*/sshd_config /etc/ssh/sshd_config
systemctl restart sshd

# Disable UFW
ufw disable
```

## Common Issues & Solutions

### Issue: Script stops after "Testing local SSH connectivity"
**Cause:** Ubuntu 24.04 uses systemd socket activation (ssh.socket) which prevents SSH from binding to new ports.

**Solution:** Fixed in latest version - script now automatically stops ssh.socket before configuring ports.

### Issue: "Permission denied (publickey)" when connecting
**Cause:** SSH key not properly saved or permissions wrong.

**Solution:**
```bash
# Ensure key has correct permissions
chmod 600 ~/.ssh/your_key

# Use correct username (sysadmin, not your old user)
ssh -p 2202 -i ~/.ssh/your_key sysadmin@server-ip
```

### Issue: "Password change required" loop
**Cause:** User account requires password change on first login, blocking SSH key auth.

**Solution:** Fixed in latest version - script no longer forces password change. If encountered:
```bash
# From console/another session:
sudo chage -d -1 sysadmin
```

### Issue: SCP connection times out
**Cause:** Trying to connect on old port 22 after hardening.

**Solution:** Use port 2202 with `-P` (capital P):
```bash
scp -P 2202 -i ~/.ssh/key file.txt sysadmin@server:/tmp/
```

### Issue: Test suite fails on UFW outgoing policy
**Cause:** Different UFW versions display status differently.

**Solution:** Fixed in latest test suite - now checks multiple output formats.

## Safety Checklist

Before running on production:

- [ ] Test on fresh VM first
- [ ] Verify stable SSH connection
- [ ] Have console/IPMI access ready
- [ ] Backup important data
- [ ] Review `SERVER_HARDENING_PLAN.md`
- [ ] Read recovery instructions
- [ ] Save SSH key and password when displayed

## Compatibility

- ✅ Ubuntu 24.04 LTS (fully tested)
- ⚠️ Ubuntu 22.04 LTS (may work, not tested)
- ❌ Other distributions (not supported)

## Contributing

Feel free to submit issues and enhancement requests.

## License

MIT License - See repository for details.

## Support

For issues or questions:
1. Check `TEST_GUIDE.md` troubleshooting section
2. Review log files in `/var/log/`
3. Check recovery instructions in `/root/`

---

**⚠️ Warning:** These scripts modify critical system configurations. Always test on non-production systems first.
