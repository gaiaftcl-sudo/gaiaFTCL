#!/usr/bin/env bash
# Terminal.app + full forest provision loop (headed Playwright).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="$ROOT"
exec bash "$ROOT/scripts/run_in_terminal_mac.sh" bash -lc "cd $(printf '%q' "$ROOT/services/gaiaos_ui_web") && npm run playwright:devportal:provision"
