#!/usr/bin/env bash
# Package FusionSidecarHost.app (Xcode Release) into a small DMG for operator distribution.
# Full GaiaFTCL release DMG (facade + FusionControl + membrane): scripts/build_gaiaftcl_facade_dmg.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${FUSION_SIDECAR_DMG_VERSION:-1.0.0-sidecar}"
DIST="$ROOT/dist"
# DerivedData under repo can pick up xattrs and break codesign ("resource fork…"); use /tmp.
DERIVED="${TMPDIR:-/tmp}/gaiaftcl_FusionSidecarHost_derived_${USER}"
PROJ="$ROOT/macos/FusionSidecarHost/FusionSidecarHost.xcodeproj"
DMG_NAME="FusionSidecarHost-${VERSION}.dmg"

mkdir -p "$DIST"
rm -rf "$DERIVED"

HARCH="$(uname -m)"
case "$HARCH" in
  arm64) XDEST="platform=macOS,arch=arm64" ;;
  x86_64) XDEST="platform=macOS,arch=x86_64" ;;
  *) XDEST="platform=macOS" ;;
esac
echo "━━ xcodebuild FusionSidecarHost (Release) arch=$HARCH ━━"
xcodebuild -project "$PROJ" -scheme FusionSidecarHost -configuration Release \
  -derivedDataPath "$DERIVED" ONLY_ACTIVE_ARCH=YES ARCHS="$HARCH" \
  build -destination "$XDEST"

APP="$DERIVED/Build/Products/Release/FusionSidecarHost.app"
if [[ ! -d "$APP" ]]; then
  echo "REFUSED: expected $APP"
  exit 1
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/fsh_dmg_stage.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

cp -R "$APP" "$STAGE/"
cat > "$STAGE/README.txt" << EOF
FusionSidecarHost (${VERSION})
==============================

Built from: macos/FusionSidecarHost/FusionSidecarHost.xcodeproj

Mount this DMG, then from Terminal:

  open "/Volumes/FusionSidecarHost/FusionSidecarHost.app"

Or inspect the binary:

  file "/Volumes/FusionSidecarHost/FusionSidecarHost.app/Contents/MacOS/FusionSidecarHost"

Full cell facade + FusionControl + scripts:
  bash scripts/build_gaiaftcl_facade_dmg.sh
EOF

OUT="$DIST/$DMG_NAME"
rm -f "$OUT"
hdiutil create -volname "FusionSidecarHost" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
hdiutil verify "$OUT"
shasum -a 256 "$OUT" > "$OUT.sha256"

echo "CALORIE: $OUT"
echo "SHA256: $(awk '{print $1}' "$OUT.sha256")"
