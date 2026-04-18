#!/usr/bin/env bash
set -euo pipefail

# Deploy Rust MCP to all cells via registry + docker-compose

SSH_KEY="$HOME/.ssh/ftclstack-unified"
REPO_ROOT="/Users/richardgillespie/Documents/FoT8D/GAIAOS"
REGISTRY_HOST="77.42.85.60"

CELLS=(
  "hel1-01:77.42.85.60"
  "hel1-02:135.181.88.134"
  "hel1-03:77.42.32.156"
  "hel1-04:77.42.88.110"
  "hel1-05:37.27.7.9"
  "nbg1-01:37.120.187.247"
  "nbg1-02:152.53.91.220"
  "nbg1-03:152.53.88.141"
  "nbg1-04:37.120.187.174"
)

echo "=== DEPLOYING RUST MCP TO ALL CELLS ==="
echo ""

# 1. Build multi-arch image on registry host (it has Docker buildx)
echo "1. Building multi-arch image on registry host..."

ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${REGISTRY_HOST}" bash <<'BUILD'
set -e
cd /tmp/gaiaos_ui_tester_mcp

# Build for both architectures
docker buildx build --platform linux/amd64,linux/arm64 \
  -f Dockerfile.prebuilt \
  -t localhost:5000/gaiaos-ui-tester-mcp:latest \
  --push .

echo "✅ Multi-arch image pushed to registry"
BUILD

[ $? -eq 0 ] || { echo "❌ Build failed"; exit 1; }

echo "✅ Image in registry"
echo ""

# 2. Deploy to all cells
echo "2. Deploying to all cells..."
echo ""

SUCCESS=0
FAILED=0

for CELL in "${CELLS[@]}"; do
  CELL_ID="${CELL%%:*}"
  IP="${CELL##*:}"
  
  printf "%-10s %-20s " "$CELL_ID" "$IP"
  
  # Copy compose snippet
  scp -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
    "${REPO_ROOT}/services/gaiaos_ui_tester_mcp/docker-compose.cell.yml" \
    "root@${IP}:/tmp/mcp.yml" 2>&1 | grep -v "Warning" >/dev/null || { echo "❌ COPY FAILED"; FAILED=$((FAILED+1)); continue; }
  
  # Add to docker-compose and deploy
  if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${IP}" bash <<'DEPLOY' 2>&1 | grep -v "Warning" >/dev/null
set -e
cd /opt/gaiaftcl

# Backup compose
cp docker-compose.yml docker-compose.yml.backup

# Add MCP service if not present
if ! grep -q "gaiaos-ui-tester-mcp:" docker-compose.yml; then
  cat /tmp/mcp.yml >> docker-compose.yml
fi

# Create evidence dirs
mkdir -p /var/www/gaiaftcl/cells/fusion/evidence/{ui_expected,ui_contract,agent_census,domain_tubes,closure_game,echo,mcp_calls}

# Pull and restart
docker-compose pull gaiaos-ui-tester-mcp
docker-compose up -d gaiaos-ui-tester-mcp

# Wait for health
sleep 3
curl -sS http://localhost:8900/health 2>/dev/null | grep -q healthy
DEPLOY
  then
    echo "✅ HEALTHY"
    SUCCESS=$((SUCCESS+1))
  else
    echo "❌ FAILED"
    FAILED=$((FAILED+1))
  fi
done

echo ""
echo "=== SUMMARY ==="
echo "Success: $SUCCESS / ${#CELLS[@]}"
echo "Failed:  $FAILED / ${#CELLS[@]}"

[ $FAILED -eq 0 ] && echo "✅ All cells deployed" || exit 1
