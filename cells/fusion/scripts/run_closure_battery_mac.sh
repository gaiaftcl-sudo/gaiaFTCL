#!/usr/bin/env bash
# C4 Mac spine: (1) physical GaiaFusion DMG mount witness, (2) optional Terminal.app closure battery.
# Mounting invariant: scripts/mount_gaiafusion_dmg.sh — df must show /Volumes/GaiaFusion.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "━━ C4: GaiaFusion DMG mount invariant ━━"
bash "$ROOT/scripts/mount_gaiafusion_dmg.sh"

if [[ "${CLOSURE_BATTERY_MAC_TERMINAL:-1}" == "1" ]]; then
  echo "━━ Launching closure battery in Terminal.app (headed witness) ━━"
  exec bash "$ROOT/scripts/run_in_terminal_mac.sh" bash -lc "cd $(printf '%q' "$ROOT") && bash scripts/run_closure_battery.sh"
else
  echo "━━ Running closure battery in this shell ━━"
  exec bash "$ROOT/scripts/run_closure_battery.sh"
fi
