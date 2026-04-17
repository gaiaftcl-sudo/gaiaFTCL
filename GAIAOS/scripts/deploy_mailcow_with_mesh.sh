#!/usr/bin/env bash
# Deploy Mailcow on hel1-01 with constitutional mesh integration.
# Mailcow joins gaiaftcl_cell network, uses MCP_URL only. Never touches ArangoDB directly.
#
# Prerequisite: Cell stack running (docker compose -f docker-compose.cell.yml up -d)
# Usage: ./scripts/deploy_mailcow_with_mesh.sh

set -euo pipefail

CELL_IP="${1:-77.42.85.60}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/ftclstack-unified}"
GAIA_ROOT="${GAIA_ROOT:-/opt/gaia/GAIAOS}"

echo "Deploying Mailcow with mesh on ${CELL_IP}..."

# Copy override to cell
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
  docs/specs/skin/mailcow-mesh-override.yml \
  root@${CELL_IP}:/opt/mailcow-mesh-override.yml

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@${CELL_IP} << REMOTE
  set -e
  cd /opt/mailcow-dockerized
  if [ ! -f docker-compose.yml ]; then
    echo "Mailcow not installed. Run deploy_mailcow_fleet.sh Phase 3 first."
    exit 1
  fi
  # Ensure cell network exists
  docker network inspect gaiaftcl_gaiaftcl-mesh >/dev/null 2>&1 || {
    echo "Cell stack not running. Start it first: cd ${GAIA_ROOT} && docker compose -f docker-compose.cell.yml up -d"
    exit 1
  }
  cp /opt/mailcow-mesh-override.yml .
  docker compose -f docker-compose.yml -f mailcow-mesh-override.yml up -d nginx-mailcow
  echo "Mailcow nginx joined mesh. MCP_URL=http://fot-mcp-gateway-mesh:8803"
REMOTE

echo "Done. Verify: docker exec mailcowdockerized-backup-nginx-mailcow-1 curl -s http://fot-mcp-gateway-mesh:8803/health"
