#!/usr/bin/env bash
# Deploy MCP to a single cell

CELL_IP="$1"
SSH_KEY="$HOME/.ssh/ftclstack-unified"
BUILD_HOST="77.42.85.60"

[ -z "$CELL_IP" ] && { echo "Usage: $0 <cell_ip>"; exit 1; }

echo "Deploying to $CELL_IP..."

# Get image from build host and load on target
ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${BUILD_HOST}" \
  "docker save localhost:5000/gaiaos-ui-tester-mcp:latest" | \
ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${CELL_IP}" \
  "docker load"

# Deploy (docker load already tags correctly)
ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${CELL_IP}" \
  "cd /opt/gaiaftcl && mkdir -p /var/www/gaiaftcl/GAIAOS/evidence/{ui_expected,ui_contract,agent_census,domain_tubes,closure_game,echo,mcp_calls} && docker rm -f gaiaos-ui-tester-mcp 2>/dev/null || true && docker compose up -d gaiaos-ui-tester-mcp"

# Wait and check
sleep 10
ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${CELL_IP}" \
  "curl -sS http://localhost:8900/health"
