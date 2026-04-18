#!/usr/bin/env bash
# Mount GaiaFTCL DMG to a temp mountpoint, run shell checks from the volume, detach.
# Receipt: stdout + exit 0 on success.
# Usage:
#   bash scripts/witness_gaiaftcl_dmg_mount.sh [path/to/GaiaFTCL-1.0.0.dmg]
# Env:
#   GAIA_ROOT — repo root (default: parent of scripts/)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DMG="${1:-}"
if [[ -z "$DMG" ]]; then
  V="${VERSION:-1.0.0}"
  CAND="$ROOT/dist/GaiaFTCL-${V}.dmg"
  if [[ -f "$CAND" ]]; then
    DMG="$CAND"
  else
    DMG="$(ls -t "$ROOT"/dist/GaiaFTCL-*.dmg 2>/dev/null | head -1 || true)"
  fi
fi

if [[ -z "$DMG" || ! -f "$DMG" ]]; then
  echo "REFUSED: no DMG found. Build first: bash scripts/build_gaiaftcl_facade_dmg.sh"
  echo "  or pass explicit path: bash scripts/witness_gaiaftcl_dmg_mount.sh /path/to/GaiaFTCL-1.0.0.dmg"
  exit 1
fi

MNT="$(mktemp -d "${TMPDIR:-/tmp}/gaiaftcl_dmg_witness.XXXXXX")"
cleanup() {
  hdiutil detach "$MNT" -quiet 2>/dev/null || true
  rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

echo "━━ witness: attach DMG ━━"
echo "DMG: $DMG"
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MNT"
echo "MOUNT: $MNT"
echo ""

echo "━━ volume listing (top) ━━"
ls -la "$MNT" | head -40
echo ""

run() {
  echo "━━ $* ━━"
  "$@"
  echo ""
}

run test -d "$MNT/GaiaFTCL.app"
run test -d "$MNT/FusionControl.app"
run test -x "$MNT/FusionControl.app/Contents/MacOS/fusion_control"
run test -f "$MNT/README.txt"
run test -f "$MNT/README_MEMBRANE.md"
run test -x "$MNT/bin/cell_onboard.sh"
run bash -n "$MNT/scripts/best_control_test_ever.sh"

if [[ -d "$MNT/FusionSidecarHost.app" ]]; then
  run test -d "$MNT/FusionSidecarHost.app/Contents/MacOS"
  echo "FusionSidecarHost.app: present on volume"
else
  echo "NOTE: FusionSidecarHost.app absent (DMG built with failed/skip xcodebuild or FUSION_DMG_INCLUDE_SIDECAR_HOST=0)"
fi

echo "CALORIE: DMG mount + volume smoke OK"
exit 0
