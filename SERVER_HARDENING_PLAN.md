# Ubuntu 24.04 Server Hardening Script - Implementation Plan

## Overview
Production-ready hardening script with zero-downtime guarantee and professional-grade safety mechanisms.

---

## Recommendations & Decisions

### 1. Username Recommendation
**Recommended:** `sysadmin`
- Not generic `admin` or `user` (common attack targets)
- Clear purpose without being too specific
- Alternative: `deploy` if this is a deployment server

### 2. SSH Key Strategy Recommendation
**Recommended Approach:**
- Script generates fresh Ed25519 key pair (most secure, modern standard)
- Saves private key to: `~/.ssh/server_hardening_key_<hostname>_<date>`
- Displays public key for immediate backup/copy
- **Why:** Prevents key reuse across servers, ensures key exists before disabling password auth

### 3. Professional Safety Standards
**Industry Best Practices:**
- **Test-before-commit:** Verify SSH connectivity on new port before closing old one
- **Automatic rollback:** If connection test fails, revert changes immediately
- **Configuration backup:** Store original configs in `/root/.hardening-backup-<timestamp>/`
- **Grace period:** Optional 5-minute window where you can manually revert if locked out
- **Connection verification:** Multiple SSH test attempts before considering success

### 4. Log Rotation Explanation
**What it is:** Automated management of log files to prevent disk space exhaustion
- Rotates logs daily/weekly based on size
- Compresses old logs
- Deletes logs older than X days
- **Why include:** Fresh servers generate logs quickly; without rotation, disk fills up = service downtime

---

## Implementation Requirements

### Core Safety Requirements (Non-Negotiable)
1. **Zero-lockout guarantee:** Script must verify new SSH config works before disabling current access
2. **Atomic operations:** Changes grouped; if any step fails, revert previous steps in group
3. **Backup everything:** Original configs preserved before modification
4. **Connection testing:** Mandatory SSH test on new port + new user before closing old access
5. **Emergency recovery:** Script documents exact rollback commands in `/root/RECOVERY_INSTRUCTIONS.txt`

### Phase 1: Pre-Flight Checks
1. Verify running as root
2. Check Ubuntu version (must be 24.04)
3. Detect existing SSH connection (warn if not)
4. Check available disk space (>1GB recommended)
5. Verify internet connectivity
6. Create backup directory: `/root/.hardening-backup-<timestamp>/`

### Phase 2: User Creation
1. Create user: `sysadmin`
2. Add to sudo group
3. Set strong random password (display once, require change on first login)
4. Create `.ssh` directory with proper permissions
5. Generate Ed25519 SSH key pair
6. Add public key to `sysadmin` authorized_keys

### Phase 3: SSH Hardening
**Order is CRITICAL:**
1. Backup original `/etc/ssh/sshd_config`
2. Add new config block (new port 2202, key auth, disable root)
3. Create secondary SSH service on port 2202 first (dual-port mode)
4. **TEST:** Verify can connect on port 2202 as sysadmin
5. **TEST:** Verify can connect as root still on port 22 (fallback)
6. Only after successful tests: Remove port 22, disable root login
7. Restart SSH service
8. Final connectivity test

### Phase 4: Firewall (UFW)
1. Backup current rules
2. Set default policies: deny incoming, allow outgoing
3. Allow port 2202/tcp (new SSH)
4. Enable UFW with --force (non-interactive)
5. Verify SSH still works

### Phase 5: Fail2ban
1. Install fail2ban
2. Backup original configs
3. Configure SSH jail for port 2202
4. Set reasonable defaults (3 retries, 10min ban, 10min findtime)
5. Enable and start service
6. Verify no immediate self-ban (whitelist current IP if possible)

### Phase 6: System Hardening
1. Install and configure logrotate
2. Update all packages
3. Configure automatic security updates (unattended-upgrades)
4. Set secure file permissions on sensitive files

### Phase 7: Verification & Documentation
1. Generate security report: `/root/security-hardening-report-<timestamp>.txt`
2. Display critical information:
   - New SSH port: 2202
   - New username: sysadmin
   - SSH private key location
   - Password (display once, then clear from terminal)
   - Recovery/rollback instructions
3. Cleanup: Remove any temporary files

---

## Error Handling Strategy

### Error Categories
1. **Pre-flight errors:** Stop immediately, no changes made
2. **User creation errors:** Revert user creation, stop
3. **SSH config errors:** Restore original config, restart SSH, stop
4. **Connection test failures:** Auto-rollback to previous working state
5. **UFW errors:** Disable UFW, restore rules, continue with warning
6. **Fail2ban errors:** Log warning, continue

### Rollback Mechanism
```bash
# Each phase saves state:
- Phase 1: No rollback needed
- Phase 2: userdel -r sysadmin (if created)
- Phase 3: cp backup/sshd_config /etc/ssh/sshd_config && systemctl restart sshd
- Phase 4: ufw disable && ufw --force reset
- Phase 5: systemctl stop fail2ban && apt remove fail2ban -y
```

### Safety Checkpoints
**Checkpoint 1:** After user creation - Can switch to sysadmin?
**Checkpoint 2:** After SSH config - Can connect on port 2202?
**Checkpoint 3:** After UFW enable - SSH still accessible?
**Checkpoint 4:** Final - All services running?

---

## Connection Testing Protocol

### Test Sequence (Automated)
1. Save current SSH session info
2. Attempt SSH connection to localhost:2202 as sysadmin
3. If local test passes: Verify from remote (if script is run remotely)
4. If remote test passes: Consider SSH hardening successful
5. If ANY test fails: Immediate rollback

### Grace Period Option
- After SSH change, start 5-minute timer
- If user doesn't press "Y" to confirm access, auto-rollback
- This acts as safety net if automated tests pass but actual access fails

---

## Output & Logging

### Terminal Output
- Clear progress indicators: `[1/7] Creating user...`
- Success/failure per phase
- Critical info in standout color (port, username, key location)
- Final summary with next steps

### Log Files
- Detailed log: `/var/log/server-hardening-<timestamp>.log`
- Security report: `/root/security-hardening-report-<timestamp>.txt`
- Recovery instructions: `/root/RECOVERY_INSTRUCTIONS.txt`

---

## Edge Cases & Considerations

### Potential Issues
1. **Already configured UFW:** Save rules, merge with new ones
2. **Custom SSH config:** Parse existing, merge carefully
3. **SELinux/AppArmor:** Ubuntu 24.04 uses AppArmor; ensure compatibility
4. **Cloud-init:** Some cloud providers inject SSH keys; ensure compatibility
5. **Fail2ban self-ban:** Whitelist current IP or use very tolerant initial settings

### Non-Standard Scenarios
- Running in container (LXC/Docker): Detect and warn/adjust
- Already disabled root login: Skip that step
- SSH key already exists: Prompt to use existing or generate new

---

## Success Criteria

**Script success means:**
- [ ] New user `sysadmin` exists with sudo access
- [ ] SSH working on port 2202 with key authentication
- [ ] Root login disabled via SSH
- [ ] UFW active, allowing only port 2202 (and any user-specified ports)
- [ ] Fail2ban monitoring SSH on port 2202
- [ ] All original configs backed up
- [ ] Recovery instructions documented
- [ ] User can still access server (verified connection test)

---

## Post-Execution User Actions

After script completes, user MUST:
1. **Immediately** copy SSH private key from displayed location
2. Test connection: `ssh -i <key> sysadmin@<server> -p 2202`
3. Verify sudo works: `sudo whoami`
4. Confirm root disabled: Try `ssh root@<server> -p 2202` (should fail)
5. Save security report and recovery instructions

---

## Technical Specifications

### Script Requirements
- Language: Bash
- Target: Ubuntu 24.04 LTS
- Dependencies: openssh-server, ufw, fail2ban, logrotate, unattended-upgrades
- Privilege: Must run as root
- Interactivity: Minimal (prompt for confirmation only on critical steps)

### File Locations
- Backup dir: `/root/.hardening-backup-<timestamp>/`
- SSH key: `~/.ssh/server_hardening_key_<hostname>_<date>`
- Logs: `/var/log/server-hardening-<timestamp>.log`
- Reports: `/root/security-hardening-report-<timestamp>.txt`

---

## Implementation Checklist for LLM

When implementing this script, ensure:

### Safety Features
- [ ] Pre-flight checks validate environment
- [ ] All original configs backed up before modification
- [ ] SSH changes tested before committing (dual-port phase)
- [ ] Automated rollback on connection failure
- [ ] Grace period with auto-rollback option
- [ ] Recovery instructions generated

### Code Quality
- [ ] Modular functions for each phase
- [ ] Comprehensive error handling (trap ERR)
- [ ] Clear logging at each step
- [ ] No hardcoded values (use variables)
- [ ] Idempotent where possible (safe to re-run)

### User Experience
- [ ] Progress indicators showing current phase
- [ ] Clear display of critical information (ports, credentials)
- [ ] Colored output for readability (red=error, green=success, yellow=warning)
- [ ] Final summary with actionable next steps
- [ ] No sensitive data in logs (mask passwords)

### Testing Considerations
- [ ] Handle missing commands gracefully
- [ ] Check for already-existing user
- [ ] Verify SSH service status before/after changes
- [ ] Ensure UFW doesn't lock out current session
- [ ] Validate generated SSH key works

---

## Questions for Further Refinement

1. Should we add IP whitelisting option for SSH (only allow specific IPs)?
2. Do you want to enable automatic reboot if kernel updates require it?
3. Should we configure timezone and NTP synchronization?
4. Any specific ports to open beyond 2202 (web, database, etc.)?
5. Do you want a "dry-run" mode that shows what would change without applying?

---

**Document Version:** 1.0  
**Last Updated:** 2026-03-04  
**Target OS:** Ubuntu 24.04 LTS
