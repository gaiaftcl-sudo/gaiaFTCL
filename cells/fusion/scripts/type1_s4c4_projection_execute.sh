#!/usr/bin/env bash
# Type I public S4/C4 projection — Franklin /ask execution (fail closed if mesh down)
# Mirrors scripts/sovereign_bid_execute.sh pattern.
#
# Usage:
#   From GAIAOS: bash scripts/type1_s4c4_projection_execute.sh
#   Optional: NOMINAL_EUR=300e9 AS_OF="2026-02-18T00:00:00Z" SOURCE=founder_snapshot PHASE=0

set -euo pipefail

MESH_IP="${MESH_IP:-77.42.85.60}"
WALLET="${WALLET:-0x858e7ED49680C38B0254abA515793EEc3d1989F5}"
FRANKLIN_PORT="${FRANKLIN_PORT:-8803}"

NOMINAL_EUR="${NOMINAL_EUR:-}"
AS_OF="${AS_OF:-}"
SOURCE="${SOURCE:-unknown}"
RECEIPT_ID="${RECEIPT_ID:-}"
PHASE="${PHASE:-cross_cut}"
HORIZON="${HORIZON:-12m}"

INPUT_BLOCK=""
if [[ -n "${NOMINAL_EUR}" ]]; then
  INPUT_BLOCK="nominal_eur: ${NOMINAL_EUR}, as_of: ${AS_OF:-null}, source: ${SOURCE}"
  [[ -n "${RECEIPT_ID}" ]] && INPUT_BLOCK+=", receipt_id: ${RECEIPT_ID}"
else
  INPUT_BLOCK="nominal_eur omitted — use null and source unknown unless receipt_id provided"
fi

QUERY=$(cat <<EOF
You are executing the TYPE1_S4C4 projection runbook (cells/fusion/docs/prompts/FRANKLIN_TYPE1_S4C4_PROJECTION_RUNBOOK.md).
Return ONLY a single JSON object valid against cells/fusion/docs/schemas/type1_s4c4_projection.schema.json (no markdown prose outside one JSON block).

Hard rules: geodetic_floor_ratio MUST be 0.1. Do not fabricate discovery counts or treasury. Populate seed_t from caller inputs when provided.

Caller inputs:
- phase: ${PHASE}
- horizon: ${HORIZON}
- ${INPUT_BLOCK}

projection_id: type1-s4c4-$(date -u +%Y%m%d-%H%M%S)-shell
EOF
)

# jq -Rs . escapes the query for JSON string
QUERY_JSON=$(printf '%s' "$QUERY" | jq -Rs .)

HTTP_CODE=$(curl -sS -o /tmp/type1_s4c4_resp.json -w "%{http_code}" -X POST "http://${MESH_IP}:${FRANKLIN_PORT}/ask" \
  -H "Host: gaiaftcl.com" \
  -H "Content-Type: application/json" \
  -d "{\"query\": ${QUERY_JSON}, \"wallet_address\": \"${WALLET}\"}" ) || HTTP_CODE="000"

if [[ "${HTTP_CODE}" != "200" && "${HTTP_CODE}" != "201" ]]; then
  echo "FAIL: Franklin /ask not reachable or non-success (HTTP ${HTTP_CODE})." >&2
  echo "Set MESH_IP / FRANKLIN_PORT or start mesh services. No false executed." >&2
  [[ -f /tmp/type1_s4c4_resp.json ]] && cat /tmp/type1_s4c4_resp.json >&2 || true
  exit 1
fi

echo "--- GaiaFTCL / Franklin Response (raw) ---"
cat /tmp/type1_s4c4_resp.json
echo ""
echo "--- Try extract document / essay / JSON ---"
jq -r '.document // .essay // .' /tmp/type1_s4c4_resp.json 2>/dev/null || cat /tmp/type1_s4c4_resp.json
