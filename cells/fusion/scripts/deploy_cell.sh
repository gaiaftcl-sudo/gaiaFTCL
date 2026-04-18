#!/usr/bin/env bash
# Deploy closed cell to Debian VM mesh node. Zero external DNS—all services on internal network.
# Usage: ./scripts/deploy_cell.sh [cell_ip]
# Requires: docker compose, SSH access to Debian cell

set -euo pipefail

CELL_IP="${1:-77.42.85.60}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/ftclstack-unified}"

echo "Deploying closed cell to $CELL_IP..."

# Copy compose and build context
rsync -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  --exclude '.git' \
  --exclude 'node_modules' \
  ./ root@${CELL_IP}:/opt/gaia/cells/fusion/

# Deploy
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@${CELL_IP} << 'REMOTE'
  cd /opt/gaia/GAIAOS
  docker compose -f docker-compose.cell.yml up -d --build
  sleep 5
  curl -s http://localhost:8803/health | jq .
REMOTE

# Optional: apply constitutional firewall (MCP only door)
# Uncomment to enforce: only 8803 exposed, substrate ports blocked
# ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@${CELL_IP} "bash /opt/gaia/cells/fusion/scripts/apply_constitutional_firewall.sh"

echo "Cell deployed. Gateway: http://${CELL_IP}:8803"
