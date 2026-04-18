#!/usr/bin/env bash

# CI/build-gate: AOT Metal → Swift release build → optional GaiaFusion.app (embed USD_Core) + linkage verify.
# Env: GAIAFUSION_PACKAGE_APP=0 to skip scripts/package_gaiafusion_app.sh (SwiftPM verify only).
# Full prod seal: GAIAFUSION_PACKAGE_APP=1 GAIAFUSION_PACKAGE_DMG=1 (UDZO via package_gaiafusion_app.sh), then
# bash scripts/verify_gaiafusion_dmg_sealed.sh dist/GaiaFusion-packaged.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_PATH="${GAIAFUSION_BUILD_PATH:-/tmp/gaiafusion-release-build}"
export GAIAFUSION_BUILD_PATH="$BUILD_PATH"

bash "$ROOT/scripts/build_gaiafusion_metal_lib.sh"
swift build --package-path "$ROOT/macos/GaiaFusion" --configuration release --build-path "$BUILD_PATH"
REL_BIN="$(cd "$ROOT/macos/GaiaFusion" && swift build --package-path "$ROOT/macos/GaiaFusion" --configuration release --build-path "$BUILD_PATH" --show-bin-path)/GaiaFusion"
# C4: release binary must still resolve USD_Core on disk (SwiftPM copies framework next to executable).
bash "$ROOT/scripts/verify_gaiafusion_usd_runtime_link.sh" "$REL_BIN"

if [[ "${GAIAFUSION_PACKAGE_APP:-1}" == "1" ]]; then
  export GAIAFUSION_PACKAGE_CONFIG=release
  bash "$ROOT/scripts/package_gaiafusion_app.sh"
fi
