#!/usr/bin/env bash
# Stop all GaiaFusion Mach-O processes — **single Mac cell** invariant (one LocalServer / one UI stack).
# After reboot, stale UEs processes are gone; the app now enforces a single GUI instance (flock + LSMultipleInstancesProhibited).
#
# Never use `pkill -f GaiaFusion`: that matches zsh/Cursor argv, paths under .../macos/GaiaFusion/, xctest, etc.
# Always match the **executable name** only: `pgrep -x GaiaFusion` / `pkill -x GaiaFusion`.
#
# Usage: bash scripts/stop_mac_cell_gaiafusion.sh
# Exit 0 when no GaiaFusion processes remain (or none were running).
set -euo pipefail

BINARY=GaiaFusion

# Cooperative quit first (AppKit lifecycle). With many stuck instances, osascript can block — cap wait at 6s.
(
  osascript -e 'tell application "GaiaFusion" to quit' 2>/dev/null &
  ospid=$!
  ( sleep 6; kill "$ospid" 2>/dev/null ) &
  wait "$ospid" 2>/dev/null || true
) || true
sleep 1

pids_of() {
  pgrep -x "$BINARY" 2>/dev/null || true
}

round_kill() {
  local sig=$1
  local p pid
  p=$(pids_of)
  [[ -z "$p" ]] && return 0
  for pid in $p; do
    kill -s "$sig" "$pid" 2>/dev/null || true
  done
}

p=$(pids_of)
if [[ -z "$p" ]]; then
  echo "CALORIE: Mac cell clear (no ${BINARY} processes)"
  exit 0
fi

echo "Stopping ${BINARY} PIDs: $p"
round_kill TERM
sleep 2

p=$(pids_of)
if [[ -n "$p" ]]; then
  echo "SIGKILL stragglers: $p"
  round_kill KILL
  sleep 1
fi

if p=$(pids_of); [[ -n "$p" ]]; then
  echo "killall -KILL ${BINARY} (last resort)" >&2
  killall -KILL "$BINARY" 2>/dev/null || true
  sleep 1
fi

if p=$(pids_of); [[ -n "$p" ]]; then
  echo "REFUSED: ${BINARY} still running after quit/TERM/KILL/killall — PIDs: $p" >&2
  echo "Hint: Activity Monitor → GaiaFusion → Force Quit, or reboot if processes show uninterruptible wait (UE)." >&2
  exit 1
fi

echo "CALORIE: Mac cell stopped (${BINARY} — single-cell invariant restored)"
