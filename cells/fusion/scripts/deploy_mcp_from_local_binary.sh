#!/usr/bin/env bash
set -euo pipefail

# Deploy MCP using the already-built local binary to all cells
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SSH_KEY="$HOME/.ssh/ftclstack-unified"
BINARY="${REPO_ROOT}/services/gaiaos_ui_tester_mcp/target/release/gaiaos_ui_tester_mcp"

# Check binary exists and is Linux
if [ ! -f "$BINARY" ]; then
  echo "❌ Binary not found: $BINARY"
  exit 1
fi

echo "=== DEPLOYING MCP BINARY TO ALL CELLS ==="
echo "Binary: $(ls -lh $BINARY | awk '{print $5}')"
echo ""

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
  
  echo "Deploying to $CELL_ID ($IP)..."
  
  # Copy binary and Dockerfile, build minimal image on cell
  if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${IP}" \
    "mkdir -p /tmp/mcp_deploy" < /dev/null 2>&1; then
    
    # Copy binary
    if scp -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
      "$BINARY" "root@${IP}:/tmp/mcp_deploy/gaiaos_ui_tester_mcp" 2>&1; then
      
      # Build minimal Docker image on cell
      if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${IP}" bash <<'REMOTE_SCRIPT' 2>&1
cd /tmp/mcp_deploy
cat > Dockerfile <<'DOCKERFILE'
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates libssl3 curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY gaiaos_ui_tester_mcp /app/gaiaos_ui_tester_mcp
RUN chmod +x /app/gaiaos_ui_tester_mcp
RUN mkdir -p /app/evidence/{ui_expected,ui_contract,agent_census,domain_tubes,closure_game,echo,mcp_calls}
ENV RUST_LOG=info
ENV MCP_PORT=8900
EXPOSE 8900
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 CMD curl -f http://localhost:8900/health || exit 1
CMD ["/app/gaiaos_ui_tester_mcp"]
DOCKERFILE

docker build -t localhost:5000/gaiaos-ui-tester-mcp:latest .

# Ensure registry is running
cd /opt/gaiaftcl
docker compose up -d registry
sleep 2

# Push to registry
docker push localhost:5000/gaiaos-ui-tester-mcp:latest

# Deploy MCP
docker rm -f gaiaos-ui-tester-mcp 2>/dev/null || true
docker compose pull gaiaos-ui-tester-mcp
docker compose up -d gaiaos-ui-tester-mcp
sleep 3
curl -sS http://localhost:8900/health
REMOTE_SCRIPT
      then
        echo "✅ $CELL_ID deployed successfully"
        ((SUCCESS++))
      else
        echo "❌ $CELL_ID deployment failed"
        ((FAILED++))
      fi
    else
      echo "❌ $CELL_ID binary copy failed"
      ((FAILED++))
    fi
  else
    echo "❌ $CELL_ID unreachable"
    ((FAILED++))
  fi
done

echo ""
echo "=== DEPLOYMENT SUMMARY ==="
echo "Success: $SUCCESS"
echo "Failed: $FAILED"

if [ $FAILED -eq 0 ]; then
  echo "✅ All cells deployed successfully"
  exit 0
else
  echo "⚠️  Some deployments failed"
  exit 1
fi
