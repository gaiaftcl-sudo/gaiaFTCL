#!/usr/bin/env zsh
# Franklin cell — receipt v1 conformance (no mocks: validates real JSON shape against docs + schema).
set -euo pipefail
# This file lives in cells/franklin/tests/ — repo root is two levels above cells/franklin
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/_franklin_bin.zsh"
franklin_require_bin
VALIDATOR=("$FRANKLIN_BIN" validate-receipt-v1)
FIXTURE="$ROOT/tests/fixtures/minimal_receipt_v1.json"

echo "== 1) Golden fixture"
"${VALIDATOR[@]}" "$FIXTURE"

echo "== 2) Invalid receipt (missing note) must fail"
if echo '{"schema":"franklin_mac_admin_gamp5_receipt_v1","ts_utc":"2026-01-01T000000Z","git_short_sha":"x","repo_root":"/","zero_human_automation":true,"franklin_mac_admin_cell_role":"self_heal_mesh_head_game_loop","smoke_mode":true,"final_exit":0,"phases":[]}' | python3 "$VALIDATOR" 2>/dev/null; then
  echo "expected validation failure" >&2
  exit 1
fi
echo "(ok, failed as expected)"

echo "== 3) Optional end-to-end smoke (self-test + dry-run only, no Console xcodegen)"
if [[ "${RUN_FRANKLIN_E2E:-0}" == "1" ]]; then
  export FRANKLIN_INCLUDE_CONSOLE_VERIFY=0
  export FRANKLIN_GAMP5_SMOKE=1
  # shellcheck source=../../health/scripts/franklin_mac_admin_gamp5_zero_human.sh
  sh "$REPO/cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh"
  latest="$(ls -t "$REPO/cells/health/evidence"/franklin_mac_admin_gamp5_*.json 2>/dev/null | head -1)"
  if [[ -z "$latest" ]]; then
    echo "no receipt written" >&2
    exit 1
  fi
  echo "validating $latest"
  "${VALIDATOR[@]}" "$latest"
else
  echo "skip (set RUN_FRANKLIN_E2E=1 to run Franklin script + validate emitted receipt)"
fi

echo "Franklin receipt v1 conformance: OK"
