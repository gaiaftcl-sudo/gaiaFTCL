#!/usr/bin/env bash
# Create the five sovereign S4 game-room mailboxes on Mailcow via MCP Gateway → mailcow-bridge.
# Prerequisites: gateway reachable from where you run this; bridge on cell with Docker + Mailcow DB.
#
# Usage:
#   export CALLER_ID="your-internal-caller-id"
#   export MCP_GATEWAY_URL="http://127.0.0.1:8803"   # or https://gaiaftcl.com:8803 from VPN/etc.
#   export GAME_ROOM_MAILBOX_PASSWORD='long-random-shared-or-use-per-slot-vars'
#   ./scripts/init_sovereign_game_room_mailboxes.sh
#
# Per-mailbox passwords (optional overrides):
#   PW_RESEARCH PW_GOVERNANCE PW_DISCOVERY PW_SOVEREIGN PW_OPS
#
# See: docs/MAILCOW_S4_C4_SOVEREIGN_GAME_ROOMS.md

set -euo pipefail

CALLER_ID="${CALLER_ID:-}"
MCP_GATEWAY_URL="${MCP_GATEWAY_URL:-http://127.0.0.1:8803}"
BASE="${MCP_GATEWAY_URL%/}"

if [[ -z "$CALLER_ID" ]]; then
  echo "ERROR: set CALLER_ID (required by gateway for /mailcow/mailbox)." >&2
  exit 1
fi

DEFAULT_PW="${GAME_ROOM_MAILBOX_PASSWORD:-}"
if [[ -z "$DEFAULT_PW" ]]; then
  echo "ERROR: set GAME_ROOM_MAILBOX_PASSWORD (or all PW_* variables)." >&2
  exit 1
fi

PW_RESEARCH="${PW_RESEARCH:-$DEFAULT_PW}"
PW_GOVERNANCE="${PW_GOVERNANCE:-$DEFAULT_PW}"
PW_DISCOVERY="${PW_DISCOVERY:-$DEFAULT_PW}"
PW_SOVEREIGN="${PW_SOVEREIGN:-$DEFAULT_PW}"
PW_OPS="${PW_OPS:-$DEFAULT_PW}"

health="$(curl -sS -o /dev/null -w "%{http_code}" "${BASE}/health" || echo 000)"
if [[ "$health" != "200" && "$health" != "201" ]]; then
  echo "BLOCKED: MCP Gateway /health not OK at ${BASE} (http ${health}). Log to ops@ when channel returns." >&2
  exit 3
fi

create_mb() {
  local local_part="$1"
  local name="$2"
  local password="$3"
  local body
  body="$(jq -n \
    --arg c "$CALLER_ID" \
    --arg lp "$local_part" \
    --arg n "$name" \
    --arg p "$password" \
    '{caller_id:$c, local_part:$lp, name:$n, password:$p, domain:"gaiaftcl.com"}')"
  echo "Creating ${local_part}@gaiaftcl.com ..."
  resp="$(curl -sS -w "\n%{http_code}" -X POST "${BASE}/mailcow/mailbox" \
    -H "Content-Type: application/json" \
    -d "$body")"
  code="$(echo "$resp" | tail -n1)"
  json="$(echo "$resp" | sed '$d')"
  echo "$json" | jq . 2>/dev/null || echo "$json"
  if [[ "$code" != "200" && "$code" != "201" ]]; then
    echo "WARNING: HTTP $code for ${local_part}" >&2
  fi
}

create_mb "research"   "S4 Game Room — Owl Protocol (research)"    "$PW_RESEARCH"
create_mb "governance" "S4 Game Room — Mother Protocol (governance)" "$PW_GOVERNANCE"
create_mb "discovery"  "S4 Game Room — Materials discovery"        "$PW_DISCOVERY"
create_mb "sovereign"   "S4 Game Room — Consortium / treasury"      "$PW_SOVEREIGN"
create_mb "ops"         "S4 Game Room — Infrastructure / unresolved"  "$PW_OPS"

echo ""
echo "List mailboxes (verify):"
curl -sS "${BASE}/mailcow/mailboxes?caller_id=${CALLER_ID}" | jq .

echo ""
echo "Next: configure Mailcow Sieve/Rspamd routing per docs/MAILCOW_S4_C4_SOVEREIGN_GAME_ROOMS.md"
echo "Witness: copy evidence/mailcow_s4_c4/WITNESS_TEMPLATE.md and fill after Step 5 tests."
