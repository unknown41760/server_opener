#!/bin/bash
# Vaultwarden LXC Hardening Script for Proxmox
# Run INSIDE the LXC container as root

set -e

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

echo "=== Vaultwarden LXC Hardening ==="

# Make a new user instead of root
sudo adduser --gecos "" warden
sudo usermod -aG sudo warden

# 1. Update System (LXC safe)
echo "[1/7] Updating system..."
apt update && apt upgrade -y
apt install -y fail2ban ufw curl

# SSH Hardening
echo "[2/7] Configuring SSH on port 2244..."
sed -i 's/^#*Port 22/Port 2244/' /etc/ssh/sshd_config
systemctl restart sshd

# 3. Configure Firewall (LXC - UFW only)
echo "[3/7] Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
# Only allow from Proxmox host or specific IPs
# If directly exposed:
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 8081/tcp
# Allow SSH only from Proxmox host (adjust IP)
ufw allow from 192.168.77.0/24 to any port 2244
ufw --force enable

# 4. Configure Fail2ban for Vaultwarden
echo "[4/7] Setting up Fail2ban..."
cat > /etc/fail2ban/jail.d/vaultwarden.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = 2244
filter = sshd
banaction = %(banaction_allports)s
logpath = /var/log/auth.log
maxretry = 3

[vaultwarden]
enabled = true
port = 80,443,8081
filter = vaultwarden
banaction = %(banaction_allports)s
logpath = /var/log/vaultwarden.log
maxretry = 5
bantime = 7200
findtime = 14400
EOF

# Create Vaultwarden filter
cat > /etc/fail2ban/filter.d/vaultwarden.local << 'EOF'

[INCLUDES]
before = common.conf

[Definition]
failregex = ^.*?Username or password is incorrect\. Try again\. IP: <ADDR>\. Username:.*$
            ^.*?Invalid user.*ip:<HOST>.*$
ignoreregex =
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# 5. Vaultwarden Security Configuration
echo "[5/7] Configuring Vaultwarden security..."
mkdir -p /opt/vaultwarden
cat >> /opt/vaultwarden/.env << 'EOF'

# Disable signups (invite only)
SIGNUPS_ALLOWED=false
SIGNUPS_VERIFY=true

EOF

# 6. LXC-specific: Resource limits check
echo "[6/7] Checking resources..."
echo "Current memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "Current disk: $(df -h / | awk 'NR==2 {print $2}')"

# 7. Proxmox-specific: Notes for host-level security
echo "[7/7] Proxmox host configuration notes..."
cat << 'EOF'

=== MANUAL STEPS REQUIRED ON PROXMOX HOST ===

1. Firewall on Proxmox node (Datacenter → Firewall):
   - Create security group for Vaultwarden
   - Allow from anywhere if public service

2. LXC Container Options:
   - Features: nesting=1 (if using Docker inside)
   - Unprivileged container: Keep enabled (more secure)

3. Backup in Proxmox:
   - Add container to backup schedule
   - Include /backup directory from container

4. SSL Options:
   a) Caddy auto-SSL (requires port 80/443 open)
   b) Cloudflare origin certificates
   c) Let's Encrypt via Proxmox reverse proxy

5. Monitoring:
   - Install Uptime Kuma on another LXC
   - Monitor https://vaultwarden.yourdomain.com

=== POST-INSTALLATION STEPS ===

1. Access admin panel:
   https://your-domain.com/admin
   Enter ADMIN_TOKEN from /opt/vaultwarden/.env

2. Configure in Admin Panel:
   - Disable signups → Invite only
   - Set password policy (min 12 chars)
   - Enable 2FA requirement
   - Set session timeout

3. Create organization for company use
   - Invite users via email
   - Set up collections (folders)

4. Test backup restore:
   - Stop vaultwarden
   - Restore from /backup/db-*.bak
   - Verify data intact

EOF

echo "=== Hardening Complete ==="
