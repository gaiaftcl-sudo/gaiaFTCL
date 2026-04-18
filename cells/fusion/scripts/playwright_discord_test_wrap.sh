#!/usr/bin/env bash
# Run witness preflight (with --emit-export), then Playwright. Fails closed if preflight REFUSED.
# Usage: bash scripts/playwright_discord_test_wrap.sh gaiaftcl|face_of_madness [strict]
# strict=1 sets DISCORD_TIER_B_STRICT=1 (GaiaFTCL lane only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI="$ROOT/services/gaiaos_ui_web"
PROFILE="${1:?profile}"
STRICT="${2:-0}"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

ec=0
bash "$ROOT/scripts/playwright_discord_witness_preflight.sh" "$PROFILE" --emit-export >"$TMP" || ec=$?
if [[ "$ec" -ne 0 ]]; then
  exit "$ec"
fi

# shellcheck disable=SC1090
source "$TMP"

cd "$UI"
pl="$(printf '%s' "$PROFILE" | tr '[:upper:]' '[:lower:]')"
case "$pl" in
  gaiaftcl | gaia)
    export DISCORD_PLAYWRIGHT_PROFILE=gaiaftcl
    [[ "$STRICT" == "1" ]] && export DISCORD_TIER_B_STRICT=1
    ;;
  face_of_madness | fom)
    export DISCORD_PLAYWRIGHT_PROFILE=face_of_madness
    ;;
  *)
    echo "REFUSED: unknown profile '$PROFILE'" >&2
    exit 2
    ;;
esac

exec npx playwright test --config=playwright.discord.config.ts
