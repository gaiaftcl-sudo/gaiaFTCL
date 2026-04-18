#!/usr/bin/env bash
# Optional: POST Mac fleet / local mesh witness to gateway universal_ingest (mcp_claims path) and record C4 receipt.
# Requires GAIAFTCL_GATEWAY_URL + GAIAFTCL_INTERNAL_KEY. Without them: REFUSED receipt only (no WAN call).
set -euo pipefail

GAIA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EV="${GAIA_ROOT}/evidence/fusion_control"
OUT_JSON="${1:-$EV/mac_vqbit_substrate_ingest_receipt.json}"
WITNESS_JSON="${MAC_CELL_WITNESS_JSON:-$EV/mac_cell_fleet_health_witness.json}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

GATEWAY="${GAIAFTCL_GATEWAY_URL:-}"
KEY="${GAIAFTCL_INTERNAL_KEY:-}"
mkdir -p "$(dirname "$OUT_JSON")"
tmp="${OUT_JSON}.$$.tmp"

if [[ -z "$GATEWAY" || -z "$KEY" ]]; then
  jq -n \
    --arg ts "$TS" \
    --arg wpath "$WITNESS_JSON" \
    '{
      schema: "gaiaftcl_mac_vqbit_substrate_ingest_v1",
      ts_utc: $ts,
      terminal: "REFUSED",
      reason: "missing_gateway_credentials",
      note: "Set GAIAFTCL_GATEWAY_URL and GAIAFTCL_INTERNAL_KEY for live universal_ingest; optional MAC_CELL_WITNESS_JSON for fleet payload.",
      witness_path: $wpath
    }' >"$tmp"
  mv "$tmp" "$OUT_JSON"
  echo "REFUSED: GAIAFTCL_GATEWAY_URL + GAIAFTCL_INTERNAL_KEY required for ingest — wrote $OUT_JSON" >&2
  exit 2
fi

PAYLOAD_EXTRA="{}"
if [[ -f "$WITNESS_JSON" ]]; then
  PAYLOAD_EXTRA="$(jq -c '{fleet_witness: .}' "$WITNESS_JSON" 2>/dev/null || echo "{}")"
fi

BASE="${GATEWAY%/}"
BODY="$(jq -n \
  --arg ts "$TS" \
  --argjson extra "$PAYLOAD_EXTRA" \
  '{
    type: "mac_vqbit_mesh_witness",
    from: "mac_cell_mount",
    payload: ($extra + {ts_utc: $ts, source: "witness_mac_vqbit_substrate_ingest.sh"})
  }')"

HTTP_CODE="$(curl -sS -o "$tmp.http_body" -w '%{http_code}' -X POST "$BASE/universal_ingest" \
  -H "Content-Type: application/json" \
  -H "X-Gaiaftcl-Internal-Key: $KEY" \
  -d "$BODY" || echo "000")"

TERM="REFUSED"
if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
  TERM="CALORIE"
fi

jq -n \
  --arg ts "$TS" \
  --arg term "$TERM" \
  --arg code "$HTTP_CODE" \
  --arg url "$BASE/universal_ingest" \
  --arg wpath "$WITNESS_JSON" \
  --rawfile body "$tmp.http_body" \
  '{
    schema: "gaiaftcl_mac_vqbit_substrate_ingest_v1",
    ts_utc: $ts,
    terminal: $term,
    http_code: ($code|tonumber),
    ingest_url: $url,
    witness_path: $wpath,
    response_body: $body
  }' >"$tmp"
rm -f "$tmp.http_body"
mv "$tmp" "$OUT_JSON"

if [[ "$TERM" != "CALORIE" ]]; then
  echo "REFUSED: universal_ingest HTTP $HTTP_CODE — $OUT_JSON" >&2
  exit 1
fi
echo "CALORIE: universal_ingest OK — $OUT_JSON"
exit 0
