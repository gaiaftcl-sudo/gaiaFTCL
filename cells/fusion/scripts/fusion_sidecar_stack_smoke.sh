#!/usr/bin/env bash
# Bring up fusion-sidecar (Arango + gateway + tester) and assert Mac full-cell MCP probes pass.
# No GaiaFusion app build — use before verify_gaiafusion_working_app.sh when operator needs substrate-only C4.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
COMPOSE="$ROOT/docker-compose.fusion-sidecar.yml"

echo "━━ fusion_sidecar_stack_smoke: docker compose up ━━"
docker compose -f "$COMPOSE" up -d --build

echo "━━ fusion_sidecar_stack_smoke: mcp_mac_cell_probe ━━"
OUT="$(python3 "$ROOT/scripts/mcp_mac_cell_probe.py")"
echo "$OUT"
FAIL="$(echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('fail') or '')")"
if [[ -n "$FAIL" ]]; then
  echo "REFUSED: Mac full-cell probe failed: $FAIL" >&2
  exit 1
fi

echo "CURE: fusion_sidecar_stack_smoke"
exit 0
