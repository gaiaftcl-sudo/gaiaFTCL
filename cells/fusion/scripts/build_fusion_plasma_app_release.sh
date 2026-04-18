#!/usr/bin/env bash
# Production plasma operator shell: FusionSidecarHost.app (Release) via xcodebuild.
# Invariant first gate — fails closed (REFUSED) on any compiler or bundle error.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJ="$ROOT/macos/FusionSidecarHost/FusionSidecarHost.xcodeproj"
SCHEME="FusionSidecarHost"
CONFIG="Release"
# DerivedData outside repo avoids xattr / codesign noise on some filesystems.
DERIVED="${TMPDIR:-/tmp}/gaiaftcl_plasma_invariant_derived_${USER}"
STAGE_APP="$ROOT/build/plasma_release/FusionSidecarHost.app"
EVID_DIR="$ROOT/evidence/mac_fusion"
WITNESS="$EVID_DIR/FUSION_PLASMA_APP_BUILD_WITNESS.json"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "REFUSED: FusionSidecarHost Release build requires macOS (Darwin)" >&2
  exit 1
fi

if [[ ! -d "$PROJ" ]]; then
  echo "REFUSED: missing Xcode project: $PROJ" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "REFUSED: xcodebuild not in PATH (install Xcode CLI tools)" >&2
  exit 1
fi

mkdir -p "$EVID_DIR" "$ROOT/build/plasma_release"
rm -rf "$DERIVED"
mkdir -p "$DERIVED"

# Pin to host CPU — generic "platform=macOS" often builds multiple archs and fails (exit 65).
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  arm64)  XCODE_DEST="platform=macOS,arch=arm64" ;;
  x86_64) XCODE_DEST="platform=macOS,arch=x86_64" ;;
  *)
    echo "REFUSED: unsupported host arch (uname -m): $HOST_ARCH" >&2
    exit 1
    ;;
esac

echo "━━ xcodebuild $SCHEME ($CONFIG) — host_arch=$HOST_ARCH dest=$XCODE_DEST ━━"
set +e
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  ONLY_ACTIVE_ARCH=YES \
  ARCHS="$HOST_ARCH" \
  build -destination "$XCODE_DEST" 2>&1 | tee "$EVID_DIR/fusion_plasma_xcodebuild_last.log"
XC=${PIPESTATUS[0]}
set -e
if [[ "$XC" != "0" ]]; then
  echo "REFUSED: xcodebuild exit $XC (see $EVID_DIR/fusion_plasma_xcodebuild_last.log)" >&2
  exit 1
fi

BUILT="$DERIVED/Build/Products/$CONFIG/FusionSidecarHost.app"
if [[ ! -d "$BUILT" ]]; then
  echo "REFUSED: expected app bundle missing: $BUILT" >&2
  exit 1
fi

rm -rf "$STAGE_APP"
cp -R "$BUILT" "$STAGE_APP"

BIN="$STAGE_APP/Contents/MacOS/FusionSidecarHost"
if [[ ! -f "$BIN" ]]; then
  echo "REFUSED: missing main executable: $BIN" >&2
  exit 1
fi
chmod u+x "$BIN" 2>/dev/null || true
if [[ ! -x "$BIN" ]]; then
  echo "REFUSED: main executable not executable: $BIN" >&2
  exit 1
fi

SHA=$(shasum -a 256 "$BIN" | awk '{print $1}')
PLIST="$STAGE_APP/Contents/Info.plist"
SHORT_VER="unknown"
BUNDLE_ID="unknown"
if [[ -f "$PLIST" ]]; then
  SHORT_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || echo unknown)"
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null || echo unknown)"
fi

python3 - <<PY
import json, pathlib
p = pathlib.Path("$WITNESS")
doc = {
    "schema": "gaiaftcl_fusion_plasma_app_build_witness_v1",
    "app_bundle_path": "$STAGE_APP",
    "main_executable_path": "$BIN",
    "binary_sha256": "$SHA",
    "cf_bundle_short_version_string": "$SHORT_VER",
    "cf_bundle_identifier": "$BUNDLE_ID",
    "xcode_configuration": "$CONFIG",
    "derived_data_path": "$DERIVED",
    "xcodebuild_log_path": str(pathlib.Path("$EVID_DIR") / "fusion_plasma_xcodebuild_last.log"),
}
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(doc, indent=2), encoding="utf-8")
PY

echo "CALORIE: FusionSidecarHost $CONFIG → $STAGE_APP"
echo "Witness: $WITNESS"
