#!/usr/bin/env bash
# Probe nine fleet gateway health endpoints + local GaiaFusion /api/fusion/health; write JSON receipt.
# Run from a Mac with network path to cells. See deploy/mac_cell_mount/MAC_CELL_HEALTH_PROBE.md
set -euo pipefail

GAIA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_JSON="${1:-$GAIA_ROOT/evidence/fusion_control/mac_cell_fleet_health_witness.json}"
FUSION_UI_PORT="${FUSION_UI_PORT:-8910}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

IPS=(
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
IDS=(
  "gaiaftcl-hcloud-hel1-01"
  "gaiaftcl-hcloud-hel1-02"
  "gaiaftcl-hcloud-hel1-03"
  "gaiaftcl-hcloud-hel1-04"
  "gaiaftcl-hcloud-hel1-05"
  "gaiaftcl-netcup-nbg1-01"
  "gaiaftcl-netcup-nbg1-02"
  "gaiaftcl-netcup-nbg1-03"
  "gaiaftcl-netcup-nbg1-04"
)

probe_http() {
  local url="$1"
  curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 4 --max-time 12 "$url" 2>/dev/null || echo "000"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "REFUSED: jq required (brew install jq)" >&2
  exit 1
fi

fleet_lines=()
for i in "${!IPS[@]}"; do
  ip="${IPS[$i]}"
  id="${IDS[$i]}"
  code="$(probe_http "http://${ip}:8803/health")"
  fleet_lines+=("$(jq -n --arg id "$id" --arg ip "$ip" --arg c "$code" '{cell_id:$id,ipv4:$ip,http_code:($c|tonumber),url:("http://"+$ip+":8803/health")}')")
done
fleet_json="$(printf '%s\n' "${fleet_lines[@]}" | jq -s '.')"

mac_code="$(probe_http "http://127.0.0.1:${FUSION_UI_PORT}/api/fusion/health")"
mac_usd_px="null"
if [[ "$mac_code" == "200" ]]; then
  mac_usd_px="$(curl -sS --max-time 12 "http://127.0.0.1:${FUSION_UI_PORT}/api/fusion/health" | jq -c '.usd_px // null' 2>/dev/null || echo "null")"
fi

mkdir -p "$(dirname "$OUT_JSON")"
tmp="${OUT_JSON}.$$.tmp"
jq -n \
  --arg schema "gaiaftcl_mac_cell_fleet_health_witness_v1" \
  --arg ts "$TS" \
  --argjson fleet "$fleet_json" \
  --arg mac_code "$mac_code" \
  --arg mac_port "$FUSION_UI_PORT" \
  --arg mac_id "gaiaftcl-mac-fusion-leaf" \
  --argjson mac_usd_px "${mac_usd_px}" \
  '{
    schema: $schema,
    ts_utc: $ts,
    terminal: "PARTIAL",
    fleet: $fleet,
    mac_leaf: {
      cell_id: $mac_id,
      http_code: ($mac_code | tonumber),
      url: ("http://127.0.0.1:" + $mac_port + "/api/fusion/health"),
      usd_px: $mac_usd_px
    },
    note: "PARTIAL until fleet codes are 2xx from your network; Mac leaf needs GaiaFusion listening on FUSION_UI_PORT."
  }' >"$tmp"
mv "$tmp" "$OUT_JSON"

echo "CALORIE: wrote $OUT_JSON"
