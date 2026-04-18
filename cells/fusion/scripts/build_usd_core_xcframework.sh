#!/usr/bin/env bash
# Build stripped monolithic OpenUSD and assemble USD_Core_Framework.xcframework for SwiftPM.
# Prereqs: Xcode CLT, cmake (brew install cmake), python3, git.
#
# Default install prefix is under cells/fusion/Internal/Frameworks/.usd_build/gaia_usd (writable).
# For Pixar's example path /opt/local/gaia_usd, create it with sudo first:
#   sudo mkdir -p /opt/local && sudo chown "$(whoami)" /opt/local
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="${GAIA_USD_INSTALL:-$ROOT/Internal/Frameworks/.usd_build/gaia_usd}"
BUILD_ROOT="$ROOT/Internal/Frameworks/.usd_build"
OPENUSD_SRC="${OPENUSD_SRC:-$BUILD_ROOT/OpenUSD}"
OUT_XCFW="$ROOT/Internal/Frameworks/USD_Core_Framework.xcframework"
STG="$ROOT/Internal/Frameworks/.usd_staging/USD_Core.framework"

mkdir -p "$BUILD_ROOT"
if [[ ! -f "$OPENUSD_SRC/build_scripts/build_usd.py" ]]; then
  echo "Cloning OpenUSD -> $OPENUSD_SRC"
  git clone https://github.com/PixarAnimationStudios/OpenUSD.git "$OPENUSD_SRC"
fi

echo "Building USD (monolithic, no imaging/python/...) -> $INSTALL"
python3 "$OPENUSD_SRC/build_scripts/build_usd.py" \
  --no-imaging \
  --no-usdview \
  --no-python \
  --no-materialx \
  --no-ptex \
  --no-openvdb \
  --no-alembic \
  --no-draco \
  --build-monolithic \
  --no-examples \
  --no-tutorials \
  --no-tools \
  --no-tests \
  -j "${GAIA_USD_JOBS:-8}" \
  "$INSTALL"

LIB="$INSTALL/lib"
rm -rf "$STG"
mkdir -p "$STG/Versions/A/Headers" "$STG/Versions/A/Modules" "$STG/Versions/A/Frameworks"
cp "$LIB/libusd_ms.dylib" "$STG/Versions/A/USD_Core"
chmod +x "$STG/Versions/A/USD_Core"
cp -R "$INSTALL/include/pxr" "$STG/Versions/A/Headers/"
# oneTBB headers required to compile against pxr (UsdPxrBridge); ship alongside pxr in the umbrella Headers tree.
cp -R "$INSTALL/include/tbb" "$STG/Versions/A/Headers/"
cp "$LIB/libtbb.dylib" "$STG/Versions/A/Frameworks/"
install_name_tool -id "@rpath/USD_Core.framework/Versions/A/USD_Core" "$STG/Versions/A/USD_Core"
install_name_tool -change "@rpath/libtbb.dylib" "@loader_path/../Frameworks/libtbb.dylib" "$STG/Versions/A/USD_Core"
(
  cd "$STG/Versions" && ln -sfn A Current
  cd "$STG" && ln -sfn Versions/Current/Headers Headers && ln -sfn Versions/Current/Modules Modules && ln -sfn Versions/Current/USD_Core USD_Core
)

cat > "$STG/Versions/A/Modules/module.modulemap" << 'EOF'
framework module USD_Core {
  umbrella header "USD_Core.h"
  export *
  module * { export * }
}
EOF
echo '#import <Foundation/Foundation.h>' > "$STG/Versions/A/Headers/USD_Core.h"

rm -rf "$OUT_XCFW"
xcodebuild -create-xcframework -framework "$STG" -output "$OUT_XCFW"
echo "Wrote $OUT_XCFW"
otool -L "$OUT_XCFW/macos-arm64/USD_Core.framework/Versions/A/USD_Core" | head -8
