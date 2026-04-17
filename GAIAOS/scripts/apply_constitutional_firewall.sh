#!/usr/bin/env bash
# Constitutional mesh firewall: MCP (8803) is the only door.
# Substrate ports (ArangoDB, NATS, akg-gnn, substrate-generative) blocked from outside.
# Run on each cell. Requires root.
# See docs/CONSTITUTIONAL_MESH_ARCHITECTURE.md

set -euo pipefail

echo "Applying constitutional firewall rules..."

# Ensure SSH stays open (do this first)
ufw allow 22/tcp comment "SSH"

# MCP - the only door
ufw allow 8803/tcp comment "MCP Gateway - constitutional door"

# Block substrate ports from outside (Docker internal network unaffected)
ufw deny 8529/tcp comment "ArangoDB - substrate only"
ufw deny 8806/tcp comment "akg-gnn - substrate only"
ufw deny 4222/tcp comment "NATS - substrate only"
ufw deny 8805/tcp comment "substrate-generative - substrate only"

# Optional: if this cell runs web/mail, allow those
# ufw allow 80/tcp
# ufw allow 443/tcp
# ufw allow 25/tcp  # SMTP if Mailcow on this cell

ufw --force enable 2>/dev/null || true
ufw status numbered

echo "Done. Verify: ss -tlnp | grep -E '8529|8806|4222|8803|8805'"
echo "Pass: 8803 shows 0.0.0.0; others show 127.0.0.1 or internal only."
