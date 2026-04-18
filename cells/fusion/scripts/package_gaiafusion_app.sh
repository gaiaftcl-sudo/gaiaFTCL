#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

strip_bundle_xattrs() {
  local p="$1"
  [[ -e "$p" ]] || return 0
  if [[ -d "$p" ]]; then
    /usr/bin/xattr -cr "$p" 2>/dev/null || true
  fi
  /usr/bin/xattr -c "$p" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.FinderInfo "$p" 2>/dev/null || true
  /usr/bin/xattr -d 'com.apple.fileprovider.fpfs#P' "$p" 2>/dev/null || true
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "REFUSED: package_gaiafusion_app.sh requires Darwin" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/macos/GaiaFusion"
BUILD_PATH="${GAIAFUSION_BUILD_PATH:-/tmp/gaiafusion-release-build}"
CONFIG="${GAIAFUSION_PACKAGE_CONFIG:-release}"
FINAL_APP="${GAIAFUSION_APP_PATH:-/tmp/gaiafusion-delivery/GaiaFusion.app}"

if [[ "${GAIAFUSION_PACKAGE_STAGE_IN_TMP:-1}" == "1" ]]; then
  OUT_APP="${GAIAFUSION_STAGING_APP:-${TMPDIR:-/tmp}/gaiafusion-package-staging/GaiaFusion.app}"
else
  OUT_APP="$FINAL_APP"
fi
mkdir -p "$ROOT/dist"

cd "$PKG"
swift build --configuration "$CONFIG" --build-path "$BUILD_PATH"
BP="$(swift build --configuration "$CONFIG" --build-path "$BUILD_PATH" --show-bin-path)"

rm -rf "$OUT_APP"
mkdir -p "$OUT_APP/Contents/MacOS" "$OUT_APP/Contents/Resources"
BRANDING_ICNS="$PKG/GaiaFusion/Resources/Branding/AppIcon.icns"

ditto --norsrc --noextattr "$BP/GaiaFusion" "$OUT_APP/Contents/MacOS/GaiaFusion"
chmod +x "$OUT_APP/Contents/MacOS/GaiaFusion"

if [[ -d "$BP/GaiaFusion_GaiaFusion.bundle" ]]; then
  ditto --norsrc --noextattr "$BP/GaiaFusion_GaiaFusion.bundle" "$OUT_APP/Contents/Resources/GaiaFusion_GaiaFusion.bundle"
fi
if [[ -f "$BRANDING_ICNS" ]]; then
  ditto --norsrc --noextattr "$BRANDING_ICNS" "$OUT_APP/Contents/Resources/AppIcon.icns"
fi

cat >"$OUT_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>GaiaFusion</string>
  <key>CFBundleIdentifier</key>
  <string>com.gaiaftcl.GaiaFusion</string>
  <key>CFBundleName</key>
  <string>GaiaFusion</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
</dict>
</plist>
PLIST

xattr -cr "$OUT_APP" 2>/dev/null || true

TARGET_EXEC="$OUT_APP/Contents/MacOS/GaiaFusion"

ENT_SRC="$ROOT/macos/GaiaFusion/Config/GaiaFusion-entitlement.plist"
if [[ ! -f "$ENT_SRC" ]]; then
  ENT_SRC="$BP/GaiaFusion-entitlement.plist"
fi

strip_bundle_xattrs "$OUT_APP"
strip_bundle_xattrs "$OUT_APP/Contents/MacOS"
strip_bundle_xattrs "$TARGET_EXEC"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  if [[ -f "$ENT_SRC" ]]; then
    codesign --force --sign "$DEVELOPER_ID" --timestamp --entitlements "$ENT_SRC" --options runtime "$OUT_APP/Contents/MacOS/GaiaFusion" \
      || codesign --force --sign "$DEVELOPER_ID" --entitlements "$ENT_SRC" "$OUT_APP/Contents/MacOS/GaiaFusion"
  else
    codesign --force --sign "$DEVELOPER_ID" --timestamp --options runtime "$OUT_APP/Contents/MacOS/GaiaFusion"
  fi
else
  if [[ -f "$ENT_SRC" ]]; then
    codesign --force --sign - --timestamp=none --entitlements "$ENT_SRC" "$OUT_APP/Contents/MacOS/GaiaFusion" \
      || codesign --force --sign - "$OUT_APP/Contents/MacOS/GaiaFusion"
  else
    codesign --force --sign - --timestamp=none "$OUT_APP/Contents/MacOS/GaiaFusion"
  fi
fi

if [[ -d "$OUT_APP/Contents/Resources/GaiaFusion_GaiaFusion.bundle" ]]; then
  strip_bundle_xattrs "$OUT_APP/Contents/Resources/GaiaFusion_GaiaFusion.bundle"
fi
strip_bundle_xattrs "$OUT_APP"

if [[ "${GAIAFUSION_PACKAGE_CODESIGN_VERIFY:-1}" == "1" ]]; then
  strip_bundle_xattrs "$OUT_APP/Contents"
  strip_bundle_xattrs "$OUT_APP"
  echo "━━ codesign verify (strict) ━━"
  codesign -v --strict --verbose=2 "$OUT_APP" || { echo "REFUSED: codesign verify failed for $OUT_APP" >&2; exit 1; }
fi

if [[ "$OUT_APP" != "$FINAL_APP" ]]; then
  mkdir -p "$(dirname "$FINAL_APP")"
  rm -rf "$FINAL_APP"
  ditto --norsrc --noextattr "$OUT_APP" "$FINAL_APP"
  OUT_APP="$FINAL_APP"
fi

if [[ "${GAIAFUSION_COPY_TO_DIST:-0}" == "1" ]]; then
  DIST_APP="$ROOT/dist/GaiaFusion.app"
  mkdir -p "$ROOT/dist"
  rm -rf "$DIST_APP"
  ditto --norsrc --noextattr "$OUT_APP" "$DIST_APP"
fi

echo "CALORIE: GaiaFusion.app → $OUT_APP"
