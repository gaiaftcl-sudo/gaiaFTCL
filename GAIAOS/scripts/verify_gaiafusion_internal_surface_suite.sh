#!/usr/bin/env bash
# Surface suite: loopback internal HTTP CLI (when GaiaFusion is running) + Mac full cell :8803 + nine-cell MCP gateway probes.
# Full end-to-end closure remains scripts/verify_gaiafusion_working_app.sh (composite gate + self-probe + static + mac_cell + mesh).
#
# Usage:
#   With app on 8911: FUSION_UI_PORT=8911 bash scripts/verify_gaiafusion_internal_surface_suite.sh
#   Mesh only:       GAIAFUSION_INTERNAL_SUITE_SKIP_LOOPBACK=1 bash scripts/verify_gaiafusion_internal_surface_suite.sh
#   Skip local :8803: GAIAFUSION_INTERNAL_SUITE_SKIP_MAC_CELL=1 (sandbox; no Mac gateway running)
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "${GAIAFUSION_INTERNAL_SUITE_SKIP_LOOPBACK:-0}" != "1" ]]; then
  echo "━━ Loopback internal CLI (requires running GaiaFusion) ━━"
  bash "${ROOT}/scripts/gaiafusion_internal_cli.sh" "${1:-${FUSION_UI_PORT:-8910}}"
else
  echo "# Skipping loopback (GAIAFUSION_INTERNAL_SUITE_SKIP_LOOPBACK=1)"
fi

if [[ "${GAIAFUSION_INTERNAL_SUITE_SKIP_MAC_CELL:-0}" != "1" ]]; then
  echo "━━ Mac full cell MCP :8803 (local gateway — before WAN mesh) ━━"
  FAIL_MAC="$(python3 "${ROOT}/scripts/mcp_mac_cell_probe.py" | python3 -c "import sys,json; print(json.load(sys.stdin).get('fail') or '')")"
  if [[ -n "$FAIL_MAC" ]]; then
    echo "REFUSED: Mac full-cell MCP probe failed (${FAIL_MAC}) — start docker compose -f docker-compose.fusion-sidecar.yml or set GAIAFUSION_INTERNAL_SUITE_SKIP_MAC_CELL=1" >&2
    exit 1
  fi
  echo "CURE: mac full cell :8803 probes"
else
  echo "# Skipping Mac full cell (GAIAFUSION_INTERNAL_SUITE_SKIP_MAC_CELL=1)"
fi

echo "━━ Nine-cell MCP gateway :8803 (compose → fot-mcp-gateway-mesh → gaiaos-mcp-server) ━━"
bash "${ROOT}/scripts/invariant_mesh_green_probe.sh"

echo "CURE: verify_gaiafusion_internal_surface_suite"
