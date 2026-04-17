#!/usr/bin/env bash
# Probe LocalServer OpenUSD playback JSON when GaiaFusion is running on loopback.
# Usage: bash scripts/verify_gaiafusion_usd_playback.sh [port]
set -euo pipefail
PORT="${1:-8910}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVID="${ROOT}/evidence/fusion_control"
mkdir -p "$EVID"

if ! command -v curl >/dev/null 2>&1; then
  echo "REFUSED: curl required" >&2
  exit 1
fi

probe() {
  curl -fsS --connect-timeout 2 "http://127.0.0.1:${PORT}/api/fusion/openusd-playback" || true
}

JSON="$(probe)"
if [[ -z "$JSON" || "$JSON" == *"connection refused"* ]]; then
  echo "{\"terminal\":\"REFUSED\",\"reason\":\"no_listener\",\"port\":${PORT}}" | tee "${EVID}/gaiafusion_openusd_playback_probe.json"
  exit 1
fi

echo "$JSON" | tee "${EVID}/gaiafusion_openusd_playback_probe.json"
FP="$(echo "$JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(int(d.get('frames_presented',0)))" 2>/dev/null || echo 0)"
if [[ "${FP:-0}" -lt 1 ]]; then
  echo "REFUSED: frames_presented < 1 (need running GaiaFusion with Metal viewport)" >&2
  exit 1
fi
echo "CALORIE: openusd_playback frames_presented=$FP"
exit 0
