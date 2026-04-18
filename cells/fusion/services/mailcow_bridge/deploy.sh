#!/bin/bash
# Deploy mailcow-bridge to cell with Mailcow. Internal ops only (docker exec mysql/doveadm). No Mailcow HTTP API.
set -euo pipefail

CELL_IP="${CELL_IP:-77.42.85.60}"
SSH_KEY="${SSH_KEY:-~/.ssh/ftclstack-unified}"
NETWORK="${NETWORK:-gaiaftcl_gaiaftcl-mesh}"

echo "🚀 Deploying mailcow-bridge to ${CELL_IP}"

# 1. Stop existing
ssh -i ${SSH_KEY} root@${CELL_IP} "docker stop mailcow-bridge || true"
ssh -i ${SSH_KEY} root@${CELL_IP} "docker rm mailcow-bridge || true"

# 2. Copy files
ssh -i ${SSH_KEY} root@${CELL_IP} "mkdir -p /opt/gaia/mailcow_bridge"
scp -i ${SSH_KEY} mailcow_bridge.py Dockerfile requirements.txt root@${CELL_IP}:/opt/gaia/mailcow_bridge/

# 3. Build
ssh -i ${SSH_KEY} root@${CELL_IP} "cd /opt/gaia/mailcow_bridge && docker build -t gaiaftcl/mailcow-bridge:latest ."

# 4. Run (needs docker socket to exec into Mailcow containers; on mesh network for gateway)
ssh -i ${SSH_KEY} root@${CELL_IP} "docker run -d \
  --name mailcow-bridge \
  --network ${NETWORK} \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e MYSQL_CONTAINER=mailcowdockerized-backup-mysql-mailcow-1 \
  -e DOVECOT_CONTAINER=mailcowdockerized-backup-dovecot-mailcow-1 \
  -e MYSQL_PASSWORD=a7f8c9d2e3b4f1a0987654321fedcba0 \
  -e MAILCOW_DOMAIN=gaiaftcl.com \
  --restart unless-stopped \
  gaiaftcl/mailcow-bridge:latest"

echo "⏳ Waiting..."
sleep 3
ssh -i ${SSH_KEY} root@${CELL_IP} "docker exec fot-mcp-gateway-mesh curl -s http://mailcow-bridge:8840/health 2>/dev/null || echo 'Gateway cannot reach bridge yet'"
echo ""
echo "✅ mailcow-bridge deployed (internal ops only, no Mailcow API)"
