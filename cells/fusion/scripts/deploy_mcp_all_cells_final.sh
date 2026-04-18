#!/usr/bin/env bash
set -euo pipefail

# Deploy MCP to all cells - each cell has its own registry

SSH_KEY="$HOME/.ssh/ftclstack-unified"

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

echo "=== DEPLOYING MCP TO ALL CELLS ==="
echo ""

SUCCESS=0
FAILED=0

for CELL in "${CELLS[@]}"; do
  CELL_ID="${CELL%%:*}"
  IP="${CELL##*:}"
  
  printf "%-10s %-20s " "$CELL_ID" "$IP"
  
  # Transfer image from hel1-01 registry to this cell
  if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@77.42.85.60" \
    "docker save localhost:5000/gaiaos-ui-tester-mcp:latest" | \
    ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${IP}" \
    "docker load && docker tag gaiaos-ui-tester-mcp:latest localhost:5000/gaiaos-ui-tester-mcp:latest" 2>&1 | grep -v "Warning" >/dev/null
  then
    # Add to compose and start
    if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${IP}" bash <<'DEPLOY' 2>&1 | grep -v "Warning" >/dev/null
cd /opt/gaiaftcl
if ! grep -q "gaiaos-ui-tester-mcp:" docker-compose.yml; then
  cat >> docker-compose.yml <<'MCP'

  gaiaos-ui-tester-mcp:
    image: localhost:5000/gaiaos-ui-tester-mcp:latest
    container_name: gaiaos-ui-tester-mcp
    restart: unless-stopped
    environment:
      - RUST_LOG=info
      - MCP_PORT=8900
    ports:
      - "8900:8900"
    volumes:
      - /var/www/gaiaftcl/cells/fusion/evidence:/app/evidence:rw
    networks:
      gaiaftcl:
        ipv4_address: 172.31.0.41
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8900/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 5s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
MCP
fi
mkdir -p /var/www/gaiaftcl/cells/fusion/evidence/{ui_expected,ui_contract,agent_census,domain_tubes,closure_game,echo,mcp_calls}
docker-compose up -d gaiaos-ui-tester-mcp
sleep 8
curl -sS http://localhost:8900/health 2>/dev/null | grep -q healthy
DEPLOY
    then
      echo "✅ HEALTHY"
      SUCCESS=$((SUCCESS+1))
    else
      echo "❌ START FAILED"
      FAILED=$((FAILED+1))
    fi
  else
    echo "❌ IMAGE TRANSFER FAILED"
    FAILED=$((FAILED+1))
  fi
done

echo ""
echo "=== SUMMARY ==="
echo "Success: $SUCCESS / ${#CELLS[@]}"
echo "Failed:  $FAILED / ${#CELLS[@]}"
