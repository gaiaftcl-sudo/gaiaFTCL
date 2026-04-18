#!/usr/bin/env bash
# Install Franklin mesh Cycle Timer (DEPRECATED - loop mode is default)

set -euo pipefail

echo "⚠️  WARNING: Timer mode is DEPRECATED"
echo "    Franklin Guardian now runs mesh game in continuous 24/7 loop mode by default."
echo "    This timer is only needed if you explicitly disable loop mode (mesh_LOOP_ENABLED=false)."
echo ""
echo "    Recommended: Use 'install_head_autostart.sh' instead for 24/7 operation."
echo ""
read -p "Continue with timer installation? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Copy service and timer units
sudo cp franklin-mesh-cycle.service /etc/systemd/system/
sudo cp franklin-mesh-cycle.timer /etc/systemd/system/

# Create env file if missing
if [ ! -f /etc/gaiaftcl/franklin.env ]; then
    echo "Creating /etc/gaiaftcl/franklin.env (edit with your values)"
    sudo mkdir -p /etc/gaiaftcl
    sudo tee /etc/gaiaftcl/franklin.env > /dev/null <<'ENV'
# Franklin Guardian mesh Config
MCP_BASE_URL=http://localhost:8850/mcp/execute
MCP_ENV_ID=4c30d276-ec0b-48c2-9d74-b1dcd6ce67b6
mesh_SUBMOLTS=m/governance
mesh_SCAN_LIMIT=50
mesh_LOOP_ENABLED=false
ENV
    echo "✅ Created /etc/gaiaftcl/franklin.env with mesh_LOOP_ENABLED=false"
else
    echo "✅ /etc/gaiaftcl/franklin.env already exists"
fi

# Reload systemd
sudo systemctl daemon-reload

# Enable and start timer (but warn)
sudo systemctl enable franklin-mesh-cycle.timer
sudo systemctl start franklin-mesh-cycle.timer

echo ""
echo "=== Timer Installation Complete ==="
echo ""
echo "⚠️  Remember: This timer will conflict with loop mode!"
echo "    Ensure mesh_LOOP_ENABLED=false in /etc/gaiaftcl/franklin.env"
echo ""
echo "Check status:"
echo "  sudo systemctl status franklin-mesh-cycle.timer"
echo "  sudo systemctl list-timers franklin-mesh-cycle.timer"
echo ""
echo "View logs:"
echo "  sudo journalctl -u franklin-mesh-cycle.service -f"
