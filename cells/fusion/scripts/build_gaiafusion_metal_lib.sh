#!/usr/bin/env bash

# Pre-compile GaiaFusion Metal shaders into a bundle-backed `.metallib` before release build.
# This avoids runtime MSL parsing overhead during startup.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHADER_DIR="$ROOT/macos/GaiaFusion/GaiaFusion/Shaders"
OUTPUT_DIR="$ROOT/macos/GaiaFusion/GaiaFusion/Resources"
TMP_DIR="${TMPDIR:-/tmp}/gaiafusion_metal_lib_$$"
METAL_STD="${METAL_STD:-macos-metal2.0}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "REFUSED: xcrun unavailable. Install Xcode command line tools."
  exit 1
fi

mkdir -p "$OUTPUT_DIR" "$TMP_DIR"
shopt -s nullglob
shaderFiles=("$SHADER_DIR"/*.metal)
if (( ${#shaderFiles[@]} == 0 )); then
  echo "REFUSED: no .metal files found in $SHADER_DIR"
  exit 1
fi

for source in "${shaderFiles[@]}"; do
  base="$(basename "$source" .metal)"
  xcrun -sdk macosx metal -std="$METAL_STD" -c "$source" -o "$TMP_DIR/${base}.air"
done

xcrun -sdk macosx metallib "$TMP_DIR"/*.air -o "$TMP_DIR/default.metallib"
cp "$TMP_DIR/default.metallib" "$OUTPUT_DIR/default.metallib"
rm -rf "$TMP_DIR"

echo "CALORIE: $OUTPUT_DIR/default.metallib"
