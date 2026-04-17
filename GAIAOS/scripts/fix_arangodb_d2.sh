#!/bin/bash
# Fix D2: Start ArangoDB and connect to correct network.
# ArangoDB must be on gaiaftcl_gaiaftcl ONLY (not mesh) so Mailcow cannot reach it (constitutional).
# Gateway is on both gaiaftcl_gaiaftcl and gaiaftcl_gaiaftcl-mesh, so it can reach ArangoDB.
#
# Usage: ./scripts/fix_arangodb_d2.sh [cell_ip]
# Or run on cell: bash fix_arangodb_d2.sh

set -e

CELL_IP="${1:-77.42.85.60}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/ftclstack-unified}"

run() {
  if [ -n "${CELL_IP}" ] && [ "$CELL_IP" != "localhost" ] && [ "$CELL_IP" != "127.0.0.1" ]; then
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "root@${CELL_IP}" "$1"
  else
    eval "$1"
  fi
}

echo "Fixing ArangoDB for D2 (caller_id ingest)..."
run "docker rm -f gaiaftcl-arangodb 2>/dev/null || true"
run "docker run -d \
  --name gaiaftcl-arangodb \
  --network gaiaftcl_gaiaftcl \
  -p 8529:8529 \
  -e ARANGO_ROOT_PASSWORD=gaiaftcl2026 \
  -v gaiaftcl_arango-data:/var/lib/arangodb3 \
  --restart unless-stopped \
  arangodb/arangodb:3.11"
echo "Waiting for ArangoDB..."
sleep 6
run "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8529/_api/version" || true
echo ""
echo "Verifying D2 (caller_id ingest)..."
run "curl -s -o /dev/null -w 'HTTP %{http_code}' -X POST http://127.0.0.1:8803/ingest -H 'Content-Type: application/json' -d '{\"caller_id\":\"fix_d2\",\"query\":\"D2 recovery test\"}'"
echo ""
echo "Done. Run substrate suite to verify: LOCAL=1 MCP_GATEWAY_URL=http://127.0.0.1:8803 bash scripts/run_substrate_test_suite.sh"
