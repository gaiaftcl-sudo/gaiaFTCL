#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UI_DIR="$REPO_ROOT/services/gaiaos_ui_web"
EVID_DIR="$REPO_ROOT/evidence/fusion_control"
TS_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
WITNESS_JSON="$EVID_DIR/fusion_new_user_playwright_witness.json"
BANNED_RE='mock|mocks|simulate|simulated|simulation|emulation'

if [ -z "${GAIA_ROOT:-}" ]; then
  export GAIA_ROOT="$REPO_ROOT"
fi

mkdir -p "$EVID_DIR"

cd "$UI_DIR"
npm install --silent
npx playwright install chromium

# Zero-mock/simulation invariant: fail before run if selected training specs contain banned wording.
if rg -n -i -e "$BANNED_RE" tests/fusion/fusion_s4_console.spec.ts tests/fusion/fusion_dashboard_visual_witness.spec.ts >/dev/null; then
  echo "REFUSED: banned mock/simulation wording detected in onboarding specs" >&2
  rg -n -i -e "$BANNED_RE" tests/fusion/fusion_s4_console.spec.ts tests/fusion/fusion_dashboard_visual_witness.spec.ts || true
  RC=2
  cat > "$WITNESS_JSON" <<JSON
{
  "schema": "gaiaftcl_fusion_new_user_playwright_witness_v1",
  "ts_utc": "$TS_UTC",
  "gaia_root": "$GAIA_ROOT",
  "playwright_config": "services/gaiaos_ui_web/playwright.fusion.config.ts",
  "specs": [
    "tests/fusion/fusion_s4_console.spec.ts",
    "tests/fusion/fusion_dashboard_visual_witness.spec.ts"
  ],
  "rc": $RC,
  "terminal": "REFUSED",
  "reason": "banned_mock_or_simulation_wording_in_specs"
}
JSON
  exit "$RC"
fi

set +e
npx playwright test \
  --config=playwright.fusion.config.ts \
  tests/fusion/fusion_s4_console.spec.ts \
  tests/fusion/fusion_dashboard_visual_witness.spec.ts \
  --reporter=list
RC=$?
set -e

cat > "$WITNESS_JSON" <<JSON
{
  "schema": "gaiaftcl_fusion_new_user_playwright_witness_v1",
  "ts_utc": "$TS_UTC",
  "gaia_root": "$GAIA_ROOT",
  "playwright_config": "services/gaiaos_ui_web/playwright.fusion.config.ts",
  "specs": [
    "tests/fusion/fusion_s4_console.spec.ts",
    "tests/fusion/fusion_dashboard_visual_witness.spec.ts"
  ],
  "rc": $RC,
  "terminal": "$( [ "$RC" -eq 0 ] && echo CALORIE || echo REFUSED )"
}
JSON

echo "Witness: $WITNESS_JSON"
if [ "$RC" -eq 0 ]; then
  echo "CALORIE: Fusion new user Playwright walkthrough passed"
else
  echo "REFUSED: Fusion new user Playwright walkthrough failed (rc=$RC)" >&2
fi
exit "$RC"
