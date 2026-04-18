#!/bin/bash
# Phase 6 — Live S4 Observable Layer (Mac observer → Discord surface → substrate claims)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APPLE_DIR="$SCRIPT_DIR/applescript"
IDS="$APPLE_DIR/channel_ids.env"
PH6_GW_ENV="$APPLE_DIR/phase6_gateway.env"

# Optional: forest / membrane env on dev machine (gitignored)
# shellcheck source=/dev/null
[ -f "$REPO_ROOT/services/discord_frontier/.env" ] && set -a && . "$REPO_ROOT/services/discord_frontier/.env" && set +a

GATEWAY="${GAIAFTCL_GATEWAY:-http://127.0.0.1:18803}"
KEY="${GAIAFTCL_INTERNAL_KEY:-${GAIAFTCL_INTERNAL_SERVICE_KEY:-}}"

write_gateway_env() {
  umask 077
  printf 'GAIAFTCL_GATEWAY=%s\n' "$GATEWAY" >"$PH6_GW_ENV"
  printf 'GAIAFTCL_INTERNAL_KEY=%s\n' "$KEY" >>"$PH6_GW_ENV"
}

auto_channel_ids_from_env() {
  [[ -n "${DISCORD_GUILD_ID:-}" ]] || return 1
  [[ -n "${CHANNEL_ID_OWL_PROTOCOL:-}" ]] || return 1
  umask 077
  {
    echo "DISCORD_GUILD_ID=${DISCORD_GUILD_ID}"
    echo "CHANNEL_ID_OWL_PROTOCOL=${CHANNEL_ID_OWL_PROTOCOL:-}"
    echo "CHANNEL_ID_DISCOVERY=${CHANNEL_ID_DISCOVERY:-}"
    echo "CHANNEL_ID_GOVERNANCE=${CHANNEL_ID_GOVERNANCE:-}"
    echo "CHANNEL_ID_TREASURY=${CHANNEL_ID_TREASURY:-}"
    echo "CHANNEL_ID_SOVEREIGN_MESH=${CHANNEL_ID_SOVEREIGN_MESH:-}"
    echo "CHANNEL_ID_RECEIPTS=${CHANNEL_ID_RECEIPTS:-}"
    echo "CHANNEL_ID_ASK_FRANKLIN=${CHANNEL_ID_ASK_FRANKLIN:-}"
  } >"$IDS"
}

if [[ -f "$IDS" ]] && grep -qE '^DISCORD_GUILD_ID=[0-9]{5,}' "$IDS"; then
  # shellcheck source=/dev/null
  set -a && . "$IDS" && set +a
elif auto_channel_ids_from_env; then
  # shellcheck source=/dev/null
  set -a && . "$IDS" && set +a
else
  echo "BLOCKED: No valid channel_ids.env"
  echo "  Option A: copy applescript/channel_ids.env.example → applescript/channel_ids.env and fill IDs"
  echo "  Option B: export DISCORD_GUILD_ID + CHANNEL_ID_OWL_PROTOCOL (and optional others) then re-run"
  echo "  Option C: export DISCORD_GUILD_ID + bot token, then:"
  echo "    python3 $APPLE_DIR/discover_channel_ids.py"
  exit 1
fi

write_gateway_env

claims_curl() {
  local filter="$1"
  local enc
  enc="$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$filter'''))")"
  local url="${GATEWAY}/claims?filter=${enc}&limit=3"
  if [[ -n "$KEY" ]]; then
    curl -sf "$url" -H "X-Gaiaftcl-Internal-Key: ${KEY}" || true
  else
    curl -sf "$url" || true
  fi
}

check_substrate() {
  local filter="$1"
  sleep 4
  local raw
  raw="$(claims_curl "$filter")"
  local RESULT
  if [[ -z "$raw" ]]; then
    RESULT="SUBSTRATE_UNREACHABLE"
  else
    RESULT="$(printf '%s' "$raw" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d),"claims found")' 2>/dev/null || echo "SUBSTRATE_PARSE_FAIL")"
  fi
  echo "  Substrate: $RESULT"
  if [[ "$RESULT" == *"0 claims"* ]] || [[ "$RESULT" == SUBSTRATE_* ]]; then
    echo "  STATUS: FAIL — signal did not reach substrate (or filter mismatch)"
  else
    echo "  STATUS: PASS"
  fi
}

echo "═══ PHASE 6: S4 LIVE PLAY TEST SUITE ═══"
echo "Gateway: $GATEWAY"
echo "Guild:   ${DISCORD_GUILD_ID:-unset}"
echo "Membrane / app: Discord app cell routes membrane when DISCORD_MEMBRANE_ENABLED + DISCORD_MEMBRANE_ROUTING; slash /mesh is on the app bot."
echo "Game rooms (cell_base): owl-protocol→owl_protocol, discovery, governance, treasury, sovereign-mesh→sovereign_mesh, receipts→receipt_wall, ask-franklin→ask_franklin"
echo ""

echo "TEST 1 — Moor signal to owl-protocol"
osascript "$APPLE_DIR/gaia_stimulus.scpt" "owl-protocol" "/moor"
check_substrate "owl_protocol"

echo ""
echo "TEST 2 — Floor check to discovery"
osascript "$APPLE_DIR/gaia_stimulus.scpt" "discovery" "What is the current FoT score for LEUK-005?"
check_substrate "discovery"

echo ""
echo "TEST 3 — Ask Franklin"
osascript "$APPLE_DIR/gaia_stimulus.scpt" "ask-franklin" "/ask What is the current mesh health?"
check_substrate "franklin"

echo ""
echo "TEST 4 — Mesh status signal (slash may be handled by app bot; text for automation)"
osascript "$APPLE_DIR/gaia_stimulus.scpt" "sovereign-mesh" "/mesh"
check_substrate "sovereign_mesh"

echo ""
echo "TEST 5 — Receipt wall signal"
osascript "$APPLE_DIR/gaia_stimulus.scpt" "receipts" "/receipt latest"
check_substrate "receipt_wall"

echo ""
echo "TEST 6 — NATS / gateway receipt witness"
echo "  POST /envelope/close on mesh gateway…"
CLOSE_RESULT=""
if [[ -n "$KEY" ]]; then
  CLOSE_RESULT="$(curl -sf -X POST "${GATEWAY}/envelope/close" \
    -H "Content-Type: application/json" \
    -H "X-Gaiaftcl-Internal-Key: ${KEY}" \
    -d '{"terminal_state":"CALORIE","justified_by":"phase6_live_test","game_room":"owl_protocol","entity":"LEUK-005"}' || echo "CLOSE_FAILED")"
else
  CLOSE_RESULT="$(curl -sf -X POST "${GATEWAY}/envelope/close" \
    -H "Content-Type: application/json" \
    -d '{"terminal_state":"CALORIE","justified_by":"phase6_live_test","game_room":"owl_protocol","entity":"LEUK-005"}' || echo "CLOSE_FAILED")"
fi
echo "  Close result: ${CLOSE_RESULT:0:160}"

echo ""
echo "Waiting 8 seconds for receipt to appear in #receipts (if receipts bot subscribed)…"
sleep 8
echo "  Check #receipts in Discord for CALORIE | owl_protocol | LEUK-005"
echo ""

echo "═══ PHASE 6 WITNESS TABLE ═══"
echo "TEST 1 Moor signal:       see Substrate lines above"
echo "TEST 2 Floor check:       see Substrate lines above"
echo "TEST 3 Franklin ask:      see Substrate lines above"
echo "TEST 4 Mesh status:       see Substrate lines above"
echo "TEST 5 Receipt wall:      see Substrate lines above"
echo "TEST 6 NATS receipt:      Discord #receipts + close result above"
echo ""
echo "Human verification:"
echo "  1. Membrane / forest bots responded per channel"
echo "  2. #receipts shows CALORIE / owl_protocol when wired"
echo "  3. docker logs (app cell / membrane worker) if silent"
echo ""
echo "Heartbeat (daemon): $APPLE_DIR/gaia_vortex_heartbeat_daemon.sh"
echo "Jump channel: source $IDS && $APPLE_DIR/gaia_jump.sh \"\$CHANNEL_ID_OWL_PROTOCOL\""
