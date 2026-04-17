#!/usr/bin/env bash
# Pre-compile all Metal sources → default.metallib (S⁴ build artifact; moves JIT/driver spike to build time).
# Used by build_fusion_control_mac_app.sh and DMG staging. Requires Xcode CLT (xcrun metal / metallib).
#
# Outputs:
#   services/fusion_control_mac/dist/default.metallib
#   deploy/mac_cell_mount/Resources/default.metallib  (DMG / volume mount witness)
#
# Usage:
#   bash scripts/build_metal_lib.sh
#   METAL_STD=macos-metal2.0 bash scripts/build_metal_lib.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRATE="$ROOT/services/fusion_control_mac"
DIST="$CRATE/dist"
TMP="${TMPDIR:-/tmp}/fusion_metal_lib_$$"
METAL_STD="${METAL_STD:-metal3.1}"

rm -rf "$TMP"
mkdir -p "$TMP" "$DIST" "$ROOT/deploy/mac_cell_mount/Resources"

echo "[build_metal_lib] compiling shaders in $CRATE/shaders (std=$METAL_STD)"
shopt -s nullglob
for f in "$CRATE/shaders"/*.metal; do
  base="$(basename "$f" .metal)"
  xcrun -sdk macosx metal -std="$METAL_STD" -c "$f" -o "$TMP/${base}.air"
done
xcrun -sdk macosx metallib "$TMP"/*.air -o "$TMP/default.metallib"

OUT="$DIST/default.metallib"
cp "$TMP/default.metallib" "$OUT"
cp "$TMP/default.metallib" "$ROOT/deploy/mac_cell_mount/Resources/default.metallib"
rm -rf "$TMP"

echo "[build_metal_lib] CALORIE: $OUT"
echo "[build_metal_lib] CALORIE: $ROOT/deploy/mac_cell_mount/Resources/default.metallib"
