#!/usr/bin/env bash
# Between dual-user phase 1 and 2: optional real Fusion / NATS publish (no simulation).
# Exit 0 always unless DUAL_USER_PHASE2_HOOK_STRICT=1 and the hook fails.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
STRICT="${DUAL_USER_PHASE2_HOOK_STRICT:-0}"

try_nats_pub() {
  local ui="$ROOT/services/gaiaos_ui_web"
  if [[ -d "$ui" ]]; then
    (cd "$ui" && npm run -s fusion:cell-status-pub) && return 0
  fi
  return 1
}

if try_nats_pub; then
  echo "CALORIE: dual_user_phase2_hook fusion:cell-status-pub"
  exit 0
fi

echo "PARTIAL: dual_user_phase2_hook skipped (no local NATS identity or publish failed — earth patterns are head-ingestor state)"
if [[ "$STRICT" == "1" ]]; then
  exit 1
fi
exit 0
