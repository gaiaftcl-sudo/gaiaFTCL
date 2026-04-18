#!/usr/bin/env bash
# Internal HTTP CLI for GaiaFusion loopback LocalServer — automation and MCP-style callers use the same JSON as the .app
# (WASM + sidecar + WKWebView DOM snapshot). No bundled Node/Playwright in the .app; DOM parity is /api/fusion/self-probe.
#
# Usage: bash scripts/gaiafusion_internal_cli.sh [PORT]
#   PORT defaults to FUSION_UI_PORT or 8910.
#
set -euo pipefail
PORT="${1:-${FUSION_UI_PORT:-8910}}"
BASE="http://127.0.0.1:${PORT}"

if ! curl -sf --connect-timeout 2 --max-time 5 "${BASE}/api/fusion/health" >/dev/null; then
  echo "REFUSED: ${BASE} not reachable — launch GaiaFusion or set FUSION_UI_PORT" >&2
  exit 1
fi

echo "# --- GET /api/fusion/health ---"
curl -sf "${BASE}/api/fusion/health" | python3 -m json.tool

echo "# --- GET /api/fusion/self-probe (WASM + cell_stack + WKWebView evaluateJavaScript DOM) ---"
curl -sf --max-time 25 "${BASE}/api/fusion/self-probe" | python3 -m json.tool

echo "# --- GET /api/sovereign-mesh ---"
curl -sf "${BASE}/api/sovereign-mesh" | python3 -m json.tool

echo "CURE: gaiafusion_internal_cli snapshot (port ${PORT})"
