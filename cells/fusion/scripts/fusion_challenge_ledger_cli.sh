#!/usr/bin/env bash
# Apply one ledger op via CommonJS (no Next server). Reads JSON from stdin or first arg.
# Usage:
#   echo '{"op":"register_team","team_id":"lab_jet_01","hub_id":"eurofusion","source":"cli"}' | bash scripts/fusion_challenge_ledger_cli.sh
#   bash scripts/fusion_challenge_ledger_cli.sh '{"op":"set_revenue","cumulative_revenue_eur":1000,"note":"treasury export","source":"cli"}'
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
PAYLOAD="${1:-}"
if [[ -z "$PAYLOAD" ]]; then
  PAYLOAD="$(cat)"
fi
[[ -n "$PAYLOAD" ]] || { echo "REFUSED: empty payload"; exit 2; }
cd "$ROOT"
export FCL_PAYLOAD_JSON="$PAYLOAD"
node -e "
const m = require('./scripts/lib/fusion_challenge_ledger.cjs');
const root = process.env.GAIA_ROOT;
const body = JSON.parse(process.env.FCL_PAYLOAD_JSON);
console.log(JSON.stringify(m.applyLedgerOp(root, body), null, 2));
"
