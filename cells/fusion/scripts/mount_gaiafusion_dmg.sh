#!/usr/bin/env bash
# Chess Move 1: physical hdiutil attach; df must show /Volumes/GaiaFusion.
# Self-heal: if mount missing after attach, remediate (detach stale) up to 3× before hardware REFUSED.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "REFUSED: mount_gaiafusion_dmg.sh requires Darwin (hdiutil)"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${GAIAFUSION_DMG:-}"
if [[ -z "$DMG" ]]; then
  for f in "$ROOT/dist/GaiaFusion.dmg" "$ROOT/dist/"*GaiaFusion*.dmg; do
    if [[ -f "$f" ]]; then DMG="$f"; break; fi
  done
fi
if [[ -z "$DMG" || ! -f "$DMG" ]]; then
  echo "REFUSED: GaiaFusion.dmg not found. Set GAIAFUSION_DMG or place dist/GaiaFusion.dmg (volname should be GaiaFusion for /Volumes/GaiaFusion)."
  exit 1
fi

if command -v realpath >/dev/null 2>&1; then
  DMG="$(realpath "$DMG")"
fi

export DMG
MOUNTPOINT="/Volumes/GaiaFusion"

df_has_mount() {
  df -h 2>/dev/null | grep -Fq "$MOUNTPOINT"
}

remediate_stack() {
  local pass="${1:-?}"
  echo "━━ remediation $pass: detach stale volumes + settle ━━"
  export DMG
  python3 "$ROOT/scripts/hdiutil_remediate.py" --dmg "$DMG" --mountpoint "$MOUNTPOINT" || true
  # Optional: HUP disk arbitration (requires C4_DISK_ARB_RELOAD=1; may prompt for admin)
  if [[ "${C4_DISK_ARB_RELOAD:-0}" == "1" ]]; then
    killall -HUP diskarbitrationd 2>/dev/null || true
  fi
  sleep "${C4_MOUNT_SETTLE_SEC:-2}"
}

try_attach() {
  echo "━━ attach: $DMG ━━"
  set +e
  if ! hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNTPOINT" 2>/tmp/hdiutil_err.$$; then
    echo "WARN: -mountpoint $MOUNTPOINT failed; trying default volume path"
    cat /tmp/hdiutil_err.$$ >&2 || true
    hdiutil attach "$DMG" -readonly -nobrowse
  fi
  rm -f /tmp/hdiutil_err.$$ || true
  set -e
  return 0
}

if df_has_mount; then
  echo "CALORIE: already mounted: $MOUNTPOINT"
  df -h | grep -F "$MOUNTPOINT" || true
  exit 0
fi

try_attach
if df_has_mount; then
  echo "CALORIE: GaiaFusion mount witnessed (first attach)"
  df -h | grep -F "$MOUNTPOINT"
  exit 0
fi

for pass in 1 2 3; do
  remediate_stack "$pass"
  try_attach
  if df_has_mount; then
    echo "CALORIE: GaiaFusion mount witnessed after remediation $pass"
    df -h | grep -F "$MOUNTPOINT"
    exit 0
  fi
  echo "WARN: df still missing $MOUNTPOINT after remediation $pass"
done

echo "REFUSED: hardware/kernel block — /Volumes/GaiaFusion not in df after 3 remediations. Build DMG with -volname GaiaFusion or verify disk image."
df -h
exit 1
