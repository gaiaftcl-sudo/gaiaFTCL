#!/usr/bin/env bash
set -euo pipefail

# Deploy MCP server as Docker container to all cells (matching existing pattern)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SSH_KEY="$HOME/.ssh/ftclstack-unified"

echo "=== DEPLOYING MCP DOCKER TO ALL CELLS ==="
echo ""

# Build Docker image locally
echo "Building Docker image..."
cd "${REPO_ROOT}/services/gaiaos_ui_tester_mcp"

if ! docker build -t gaiaos-ui-tester-mcp:latest . 2>&1 | tail -10; then
  echo "❌ Docker build failed"
  exit 1
fi

echo "✅ Docker image built"
echo ""

# Save image to tar
IMAGE_TAR="/tmp/gaiaos-ui-tester-mcp.tar"
echo "Saving image to tar..."
docker save gaiaos-ui-tester-mcp:latest -o "$IMAGE_TAR"
echo "✅ Image saved: $(ls -lh $IMAGE_TAR | awk '{print $5}')"
echo ""

# Deploy to each cell
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

for CELL in "${CELLS[@]}"; do
  CELL_ID="${CELL%%:*}"
  IP="${CELL##*:}"
  
  echo "=== Deploying to $CELL_ID ($IP) ==="
  
  # Copy image tar
  echo "  Copying image..."
  if ! scp -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
    "$IMAGE_TAR" "root@${IP}:/tmp/gaiaos-ui-tester-mcp.tar" 2>&1 | grep -v "Warning"; then
    echo "  ❌ Failed to copy image"
    FAILED=$((FAILED + 1))
    continue
  fi
  
  # Load image and deploy
  echo "  Loading image and deploying..."
  if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${IP}" bash <<'REMOTE_SCRIPT'
    set -e
    
    # Load image
    docker load -i /tmp/gaiaos-ui-tester-mcp.tar
    rm /tmp/gaiaos-ui-tester-mcp.tar
    
    # Stop old container
    docker stop gaiaos-ui-tester-mcp 2>/dev/null || true
    docker rm gaiaos-ui-tester-mcp 2>/dev/null || true
    
    # Create evidence directories
    mkdir -p /var/www/gaiaftcl/GAIAOS/evidence/{ui_expected,ui_contract,agent_census/canon,domain_tubes,closure_game,echo,mcp_calls}
    
    # Run new container
    docker run -d \
      --name gaiaos-ui-tester-mcp \
      --restart unless-stopped \
      --network host \
      -v /var/www/gaiaftcl/GAIAOS/evidence:/app/evidence:rw \
      -e RUST_LOG=info \
      gaiaos-ui-tester-mcp:latest
    
    # Wait for health
    sleep 3
    curl -sS http://localhost:8850/health 2>/dev/null | grep -q healthy
REMOTE_SCRIPT
  then
    echo "  ✅ Deployed and healthy"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  ❌ Deployment failed"
    FAILED=$((FAILED + 1))
  fi
  
  echo ""
done

# Cleanup
rm -f "$IMAGE_TAR"

echo "=== DEPLOYMENT SUMMARY ==="
echo "Success: $SUCCESS / ${#CELLS[@]}"
echo "Failed:  $FAILED / ${#CELLS[@]}"
echo ""

if [ $FAILED -gt 0 ]; then
  echo "⚠️  Some deployments failed"
  exit 1
fi

echo "✅ All cells deployed successfully"
