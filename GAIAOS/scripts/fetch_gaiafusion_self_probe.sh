#!/usr/bin/env bash
# C4: WKWebView DOM + transparency witness from the running GaiaFusion Mac cell (loopback only).
# Remote MCP gateway :8803 does NOT serve this — it is not the Mac UI substrate.
#
# Usage:
#   FUSION_UI_PORT=8910 bash scripts/fetch_gaiafusion_self_probe.sh
#   bash scripts/fetch_gaiafusion_self_probe.sh 8910
#
# Output: full JSON to stdout; optional second arg "dom" prints only .dom_analysis (requires jq).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-${FUSION_UI_PORT:-8910}}"
MODE="${2:-full}"
URL="http://127.0.0.1:${PORT}/api/fusion/self-probe"
if ! curl -fsS -m 12 "$URL" -o /tmp/gaiafusion_self_probe.json 2>/tmp/gaiafusion_self_probe.err; then
  echo "REFUSED: GET $URL failed (is GaiaFusion running on this port?)" >&2
  cat /tmp/gaiafusion_self_probe.err >&2 || true
  exit 1
fi
if [[ "$MODE" == "dom" ]] && command -v jq >/dev/null 2>&1; then
  jq '.dom_analysis // .' /tmp/gaiafusion_self_probe.json
else
  cat /tmp/gaiafusion_self_probe.json
fi
echo >&2
echo "CALORIE: receipt also at /tmp/gaiafusion_self_probe.json" >&2
