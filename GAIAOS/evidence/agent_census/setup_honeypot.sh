#!/usr/bin/env bash
set -euo pipefail

# HONEYPOT SETUP SCRIPT — 74.208.149.139
# GaiaFTCL Agent Trap for mesh/AI Agent Detection
#
# PREREQUISITES:
# 1. Open port 49152 in IONOS firewall (for real SSH)
# 2. Port 22 will be used by Cowrie honeypot
#
# Run this script AFTER opening port 49152 in IONOS panel

HONEYPOT_IP="74.208.149.139"
HONEYPOT_PASS="UD56xX6c"
SSH_PORT="49152"

echo "=== GAIAFTCL HONEYPOT SETUP ==="
echo "Target: $HONEYPOT_IP"
echo "SSH Port: $SSH_PORT (must be open in IONOS firewall)"
echo ""

# Test connection
echo "1. Testing SSH connection on port $SSH_PORT..."
if ! sshpass -p "$HONEYPOT_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p $SSH_PORT root@$HONEYPOT_IP "echo 'Connected'"; then
  echo "❌ FAIL: Cannot connect to port $SSH_PORT"
  echo ""
  echo "ACTION REQUIRED:"
  echo "1. Go to IONOS Cloud Panel"
  echo "2. Navigate to: VPS → Firewall Policies → 74.208.149.139My firewall policy"
  echo "3. Add inbound rule: TCP port 49152"
  echo "4. Re-run this script"
  exit 1
fi

echo "✅ SSH connection working"
echo ""

# Install dependencies
echo "2. Installing Cowrie dependencies..."
sshpass -p "$HONEYPOT_PASS" ssh -p $SSH_PORT root@$HONEYPOT_IP << 'ENDSSH'
apt update
apt install -y git python3-pip python3-venv libssl-dev libffi-dev build-essential authbind
echo "✅ Dependencies installed"
ENDSSH

# Create cowrie user
echo "3. Creating cowrie user..."
sshpass -p "$HONEYPOT_PASS" ssh -p $SSH_PORT root@$HONEYPOT_IP << 'ENDSSH'
if ! id cowrie &>/dev/null; then
  adduser --disabled-password --gecos "" cowrie
  echo "✅ User cowrie created"
else
  echo "✅ User cowrie already exists"
fi
ENDSSH

# Clone and setup Cowrie
echo "4. Installing Cowrie..."
sshpass -p "$HONEYPOT_PASS" ssh -p $SSH_PORT root@$HONEYPOT_IP << 'ENDSSH'
su - cowrie << 'ENDSU'
if [ ! -d "cowrie" ]; then
  git clone https://github.com/cowrie/cowrie.git
  cd cowrie
  python3 -m venv cowrie-env
  source cowrie-env/bin/activate
  pip install --upgrade pip
  pip install -e .
  echo "✅ Cowrie installed"
else
  echo "✅ Cowrie already installed"
fi
ENDSU
ENDSSH

# Configure Cowrie
echo "5. Configuring Cowrie for GaiaFTCL agent detection..."
sshpass -p "$HONEYPOT_PASS" ssh -p $SSH_PORT root@$HONEYPOT_IP << 'ENDSSH'
su - cowrie << 'ENDSU'
cd cowrie

# Generate config if not exists
if [ ! -f etc/cowrie.cfg ]; then
  cp etc/cowrie.cfg.dist etc/cowrie.cfg
fi

# Set hostname to look like GaiaFTCL production
sed -i 's/hostname = svr04/hostname = gaia-prod-db-01/' etc/cowrie.cfg

# Create canary banner for agent detection
cat > etc/issue.net << 'BANNER'
Authorized GaiaFTCL Agents Only.
Please provide GAIA_ACK token to proceed.

Production Database Server - gaia-prod-db-01
Unauthorized access will be logged and reported.
BANNER

# Enable banner in config
if ! grep -q "banner_file = etc/issue.net" etc/cowrie.cfg; then
  sed -i '/\[ssh\]/a banner_file = etc/issue.net' etc/cowrie.cfg
fi

echo "✅ Cowrie configured"
ENDSU
ENDSSH

# Setup authbind for port 22
echo "6. Setting up port 22 redirect..."
sshpass -p "$HONEYPOT_PASS" ssh -p $SSH_PORT root@$HONEYPOT_IP << 'ENDSSH'
# Allow cowrie to bind to port 22
touch /etc/authbind/byport/22
chown cowrie /etc/authbind/byport/22
chmod 770 /etc/authbind/byport/22

# Redirect port 22 to Cowrie (port 2222)
iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222

# Make iptables persistent
apt install -y iptables-persistent
iptables-save > /etc/iptables/rules.v4

echo "✅ Port 22 redirected to Cowrie"
ENDSSH

# Start Cowrie
echo "7. Starting Cowrie honeypot..."
sshpass -p "$HONEYPOT_PASS" ssh -p $SSH_PORT root@$HONEYPOT_IP << 'ENDSSH'
su - cowrie << 'ENDSU'
cd cowrie
bin/cowrie start
sleep 2
bin/cowrie status
ENDSU
ENDSSH

echo ""
echo "=== HONEYPOT SETUP COMPLETE ==="
echo ""
echo "Honeypot IP: $HONEYPOT_IP"
echo "Honeypot Port: 22 (Cowrie trap)"
echo "Real SSH Port: $SSH_PORT"
echo ""
echo "To monitor agent activity:"
echo "  sshpass -p '$HONEYPOT_PASS' ssh -p $SSH_PORT root@$HONEYPOT_IP"
echo "  su - cowrie"
echo "  tail -f cowrie/var/log/cowrie/cowrie.json"
echo ""
echo "To test the honeypot:"
echo "  ssh root@$HONEYPOT_IP"
echo "  (Should connect to Cowrie, not real SSH)"
echo ""
echo "✅ GaiaFTCL Agent Trap is LIVE"
