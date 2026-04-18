#!/bin/bash
# Substrate Comms Organ — Master Test Runner
# Phase A must pass before B/D. All phases must pass for Field of Truth 100%.
# When run ON the head cell: LOCAL=1 MCP_GATEWAY_URL=http://127.0.0.1:8803
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Use MCP_GATEWAY_URL for GATEWAY_URL when set (e.g. on cell)
export GATEWAY_URL="${GATEWAY_URL:-${MCP_GATEWAY_URL:-http://77.42.85.60:8803}}"
# LOCAL=1: run docker/curl directly (no SSH to self when already on cell)
export LOCAL="${LOCAL:-0}"

echo "=== Substrate Test Suite ==="
echo ""

echo "=== Phase M: External social API stripped (tests first) ==="
python3 tests/substrate/test_no_external_social_api.py || exit 1
python3 tests/substrate/test_mcp_only_register.py || exit 1
python3 tests/substrate/test_mcp_only_deploy.py || exit 1
echo ""

echo "=== Phase A: Constitutional Integrity ==="
bash tests/substrate/test_constitutional_firewall.sh || exit 1
echo ""

echo "=== Phase B: Comms Organ ==="
python3 services/mailcow_bridge/tests/test_substrate_comms.py || exit 1
echo ""

echo "=== Phase D: Wallet Identity ==="
python3 tests/substrate/test_wallet_ingest.py || exit 1
echo ""

echo "=== Phase C: Spawning System (MCP-only) ==="
MCP_GATEWAY_URL="${MCP_GATEWAY_URL:-http://127.0.0.1:8803}" python3 test_spawning_system.py || exit 1
echo ""

echo "=== All substrate tests passed ==="
echo "Field of Truth: 100%"
