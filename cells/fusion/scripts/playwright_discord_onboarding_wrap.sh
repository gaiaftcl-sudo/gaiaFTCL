#!/usr/bin/env bash
# Identity onboarding: C4 witness preflight, then headed Playwright /moor -> /getmaccellfusion.
# Same witness resolution as playwright_discord_test_wrap.sh (repo, ~/.playwright-discord, discover).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI="$ROOT/services/gaiaos_ui_web"
PROFILE="${DISCORD_PLAYWRIGHT_PROFILE:-gaiaftcl}"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

bash "$ROOT/scripts/playwright_discord_witness_preflight.sh" "$PROFILE" --emit-export >"$TMP" || exit $?
# shellcheck disable=SC1090
source "$TMP"

cd "$UI"
pl="$(printf '%s' "$PROFILE" | tr '[:upper:]' '[:lower:]')"
case "$pl" in
  gaiaftcl | gaia) export DISCORD_PLAYWRIGHT_PROFILE=gaiaftcl ;;
  face_of_madness | fom) export DISCORD_PLAYWRIGHT_PROFILE=face_of_madness ;;
  *)
    echo "REFUSED: unknown DISCORD_PLAYWRIGHT_PROFILE='$PROFILE' (use gaiaftcl or face_of_madness)" >&2
    exit 2
    ;;
esac

unset CI 2>/dev/null || true

exec npx playwright test --config=playwright.discord.config.ts --grep "Discord onboarding" --headed
