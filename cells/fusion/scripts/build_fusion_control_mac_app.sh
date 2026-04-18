#!/usr/bin/env bash
# Build FusionControl.app: Rust binary + compiled Metal library (real GPU kernels).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRATE="$ROOT/services/fusion_control_mac"
DIST="$CRATE/dist"
APP="$DIST/FusionControl.app"

echo "[fusion_control_mac] cargo build --release"
( cd "$CRATE" && cargo build --release )

echo "[fusion_control_mac] Metal -> default.metallib (scripts/build_metal_lib.sh)"
bash "$ROOT/scripts/build_metal_lib.sh"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$CRATE/target/release/fusion_control" "$APP/Contents/MacOS/"
cp "$CRATE/dist/default.metallib" "$APP/Contents/Resources/"
cp "$CRATE/resources/Info.plist" "$APP/Contents/"
echo "[fusion_control_mac] built: $APP"
if [[ "${FUSION_SKIP_POST_WITNESS:-0}" != "1" ]]; then
  echo "[fusion_control_mac] witness (FUSION_VALIDATION_CYCLES=${FUSION_VALIDATION_CYCLES:-1}, FUSION_DECLARED_KW=${FUSION_DECLARED_KW:-0}):"
  "$APP/Contents/MacOS/fusion_control" || true
fi
