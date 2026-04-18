#!/usr/bin/env bash
set -euo pipefail

# Deploy MCP via registry to all cells using docker-compose

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SSH_KEY="$HOME/.ssh/ftclstack-unified"

# Use first Hetzner cell as registry
REGISTRY_HOST="77.42.85.60"
REGISTRY_URL="$REGISTRY_HOST:5000"

echo "=== DEPLOYING MCP VIA REGISTRY ==="
echo "Registry: $REGISTRY_URL"
echo ""

# 1. Build image locally
echo "1. Building Docker image..."
cd "${REPO_ROOT}/services/gaiaos_ui_tester_mcp"

if ! docker build -t gaiaos-ui-tester-mcp:latest . 2>&1 | tail -10; then
  echo "❌ Docker build failed"
  exit 1
fi

echo "✅ Image built"
echo ""

# 2. Tag for registry
echo "2. Tagging for registry..."
docker tag gaiaos-ui-tester-mcp:latest "$REGISTRY_URL/gaiaos-ui-tester-mcp:latest"
echo "✅ Tagged"
echo ""

# 3. Push to registry
echo "3. Pushing to registry..."
if ! docker push "$REGISTRY_URL/gaiaos-ui-tester-mcp:latest" 2>&1 | tail -10; then
  echo "❌ Push failed"
  exit 1
fi

echo "✅ Pushed to registry"
echo ""

# 4. Deploy to all cells
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

SUCCESS=0
FAILED=0

echo "4. Deploying to all cells..."
echo ""

for CELL in "${CELLS[@]}"; do
  CELL_ID="${CELL%%:*}"
  IP="${CELL##*:}"
  
  printf "%-10s %-20s " "$CELL_ID" "$IP"
  
  # Copy docker-compose.yml
  if ! scp -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
    "${REPO_ROOT}/services/gaiaos_ui_tester_mcp/docker-compose.yml" \
    "root@${IP}:/var/www/gaiaftcl/cells/fusion/docker-compose.mcp.yml" 2>&1 | grep -v "Warning" >/dev/null; then
    echo "❌ Failed to copy compose file"
    FAILED=$((FAILED + 1))
    continue
  fi
  
  # Deploy via docker-compose
  if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${IP}" bash <<REMOTE_SCRIPT 2>&1 | grep -v "Warning" >/dev/null
    set -e
    cd /var/www/gaiaftcl/GAIAOS
    
    # Create evidence directories
    mkdir -p evidence/{ui_expected,ui_contract,agent_census/canon,domain_tubes,closure_game,echo,mcp_calls}
    
    # Pull and deploy
    docker-compose -f docker-compose.mcp.yml pull
    docker-compose -f docker-compose.mcp.yml up -d
    
    # Wait for health
    sleep 3
    curl -sS http://localhost:8850/health 2>/dev/null | grep -q healthy
REMOTE_SCRIPT
  then
    echo "✅ HEALTHY"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "❌ FAILED"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "=== DEPLOYMENT SUMMARY ==="
echo "Success: $SUCCESS / ${#CELLS[@]}"
echo "Failed:  $FAILED / ${#CELLS[@]}"
echo ""

if [ $FAILED -gt 0 ]; then
  echo "⚠️  Some deployments failed"
  exit 1
fi

echo "✅ All cells deployed successfully"
