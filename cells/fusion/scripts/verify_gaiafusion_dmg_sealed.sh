#!/usr/bin/env bash
# Mount a GaiaFusion UDZO DMG read-only, verify codesign on the .app, and assert sealed resources
# (default.metallib, gaiafusion_substrate.wasm, AppIcon.icns) exist under the mounted tree.
#
# Usage: bash scripts/verify_gaiafusion_dmg_sealed.sh /path/to/GaiaFusion-packaged.dmg
#
set -euo pipefail

DMG="${1:?usage: verify_gaiafusion_dmg_sealed.sh path/to.dmg}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "REFUSED: verify_gaiafusion_dmg_sealed.sh requires Darwin" >&2
  exit 2
fi

if [[ ! -f "$DMG" ]]; then
  echo "REFUSED: DMG not found: $DMG" >&2
  exit 1
fi

MNT="$(mktemp -d "${TMPDIR:-/tmp}/gaiafusion-dmg-verify.XXXXXX")"

cleanup() {
  /usr/bin/hdiutil detach "$MNT" -force 2>/dev/null || true
  /bin/rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

echo "━━ hdiutil attach (read-only) ━━"
/usr/bin/hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MNT"

APP="$MNT/GaiaFusion.app"
if [[ ! -d "$APP" ]]; then
  echo "REFUSED: expected $APP in DMG volume root" >&2
  exit 1
fi

ICNS="$APP/Contents/Resources/AppIcon.icns"

echo "━━ [20] Verifying DMG Branding Invariant ━━"
/usr/bin/codesign -v --strict --verbose=2 "$APP"
if [[ ! -f "$ICNS" ]]; then
  echo "REFUSED: AppIcon.icns missing from sealed volume: $ICNS" >&2
  exit 1
fi
ICNS_BYTES="$(/usr/bin/stat -f%z "$ICNS" 2>/dev/null || echo 0)"
if [[ "${ICNS_BYTES:-0}" -lt 4096 ]]; then
  echo "REFUSED: AppIcon.icns implausible size (${ICNS_BYTES}b) — expected packed macOS iconset" >&2
  exit 1
fi
if ! /usr/bin/file "$ICNS" | /usr/bin/grep -q 'Mac OS X icon'; then
  echo "REFUSED: AppIcon.icns is not Mac OS X icon format (file(1) witness failed)" >&2
  /usr/bin/file "$ICNS" >&2
  exit 1
fi
echo "━━ mdls witness (AppIcon.icns) ━━"
/usr/bin/mdls "$ICNS" | /usr/bin/head -n 16 || true
PXW="$(/usr/bin/mdls -raw -name kMDItemPixelWidth "$ICNS" 2>/dev/null || echo "")"
if [[ -n "$PXW" && "$PXW" != "(null)" ]]; then
  echo "━━ mdls pixel width witness: ${PXW} ━━"
  if [[ "$PXW" =~ ^[0-9]+$ ]] && [[ "$PXW" -lt 8 ]]; then
    echo "REFUSED: AppIcon.icns kMDItemPixelWidth too small: $PXW" >&2
    exit 1
  fi
fi

echo "━━ resource witnesses (find) ━━"
METAL="$(/usr/bin/find "$APP" -name default.metallib -print -quit)"
WASM="$(/usr/bin/find "$APP" -name gaiafusion_substrate.wasm -print -quit)"

if [[ -z "$METAL" || ! -f "$METAL" ]]; then
  echo "REFUSED: default.metallib not found under $APP" >&2
  exit 1
fi
if [[ -z "$WASM" || ! -f "$WASM" ]]; then
  echo "REFUSED: gaiafusion_substrate.wasm not found under $APP" >&2
  exit 1
fi

echo "━━ shasum (mount-local) ━━"
/usr/bin/shasum -a 256 "$METAL" "$WASM" "$ICNS"

echo "CALORIE: DMG mount + codesign + resource witnesses ok → $DMG"
