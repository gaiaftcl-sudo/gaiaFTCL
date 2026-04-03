#!/bin/bash
# Install DNS Authority service on head cell
set -e

echo "🌐 Installing DNS Authority Service"
echo "===================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root (sudo)"
    exit 1
fi

# Build
echo "1️⃣  Building DNS Authority..."
cd "$(dirname "$0")"
cargo build --release

# Install binary
echo "2️⃣  Installing binary..."
cp target/release/dns-authority /usr/local/bin/
chmod +x /usr/local/bin/dns-authority

# Create evidence directory
echo "3️⃣  Creating evidence directory..."
mkdir -p /opt/gaia/evidence/dns_authority
chown -R root:root /opt/gaia/evidence/dns_authority

# Install systemd service
echo "4️⃣  Installing systemd service..."
cp systemd/dns-authority.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable dns-authority
systemctl restart dns-authority

# Wait for startup
echo "5️⃣  Waiting for service to start..."
sleep 3

# Check status
if systemctl is-active --quiet dns-authority; then
    echo "✅ DNS Authority is running"
else
    echo "❌ DNS Authority failed to start"
    echo "   Check logs: sudo journalctl -u dns-authority -n 50"
    exit 1
fi

# Test endpoint
echo "6️⃣  Testing endpoint..."
if curl -sf http://localhost:8804/health > /dev/null; then
    echo "✅ Health endpoint responding"
else
    echo "⚠️  Health endpoint not responding"
fi

echo ""
echo "🎉 DNS Authority Installation Complete"
echo ""
echo "Status endpoint:"
echo "  http://127.0.0.1:8804/api/dns/status"
echo ""
echo "Check status:"
echo "  curl http://127.0.0.1:8804/api/dns/status | jq"
echo ""
echo "View logs:"
echo "  sudo journalctl -u dns-authority -f"
echo ""
echo "⚠️  IMPORTANT: Ensure /etc/gaiaftcl/secrets.env contains:"
echo "  GODADDY_API_KEY=your_key"
echo "  GODADDY_API_SECRET=your_secret"
echo "  HEAD_PUBLIC_IP=77.42.85.60"
echo ""
