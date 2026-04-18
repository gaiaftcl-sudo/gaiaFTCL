#!/usr/bin/env bash
set -euo pipefail

CELLS=(
    "77.42.85.60"
    "135.181.88.134"
    "77.42.32.156"
    "77.42.88.110"
    "37.27.7.9"
    "37.120.187.247"
    "152.53.91.220"
    "152.53.88.141"
    "37.120.187.174"
)

echo "🔍 Checking All 9 Cells"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for i in "${!CELLS[@]}"; do
    cell="${CELLS[$i]}"
    echo "Cell $((i+1)): $cell"
    
    # NATS check
    NATS_STATUS=$(curl -s -m 5 "http://$cell:8222/varz" 2>/dev/null | jq -r '.server_id // "DOWN"' || echo "DOWN")
    echo "  NATS: $NATS_STATUS"
    
    # Docker containers
    CONTAINERS=$(ssh -i ~/.ssh/qfot_unified -o ConnectTimeout=5 root@$cell "docker ps --format '{{.Names}}' 2>/dev/null | wc -l" 2>/dev/null || echo "0")
    echo "  Containers: $CONTAINERS running"
    
    # Franklin check
    FRANKLIN=$(ssh -i ~/.ssh/qfot_unified -o ConnectTimeout=5 root@$cell "docker ps --format '{{.Names}}' 2>/dev/null | grep -c franklin || true" 2>/dev/null || echo "0")
    echo "  Franklin: $FRANKLIN instance(s)"
    
    echo ""
done
