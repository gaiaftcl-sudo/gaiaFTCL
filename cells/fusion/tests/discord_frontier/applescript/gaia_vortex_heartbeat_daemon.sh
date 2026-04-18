#!/bin/bash
# Runnable heartbeat (bash loop + osascript notifications). No Script Editor required.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PHASE6_APPLE_DIR="$DIR"
last=0
while true; do
  n="$("$DIR/curl_claims_count.sh" CALORIE 5 2>/dev/null || echo 0)"
  if [[ "$n" =~ ^[0-9]+$ ]] && (( n > last )); then
    d=$((n - last))
    osascript -e "display notification \"$d new receipt(s) on the wall\" with title \"GaiaFTCL — Calories or Cures\" sound name \"Glass\"" || true
    last=$n
  fi
  tor="$("$DIR/curl_torsion_state.sh" 2>/dev/null || echo NOHARM)"
  if [[ -n "$tor" && "$tor" != "NOHARM" ]]; then
    osascript -e "display notification \"System state: ${tor//\"/\\\"}\" with title \"TORSION ALERT — GaiaFTCL\" sound name \"Basso\"" || true
  fi
  sleep 30
done
