#!/usr/bin/env zsh
# Precompile Metal shaders for Apple Silicon — REQUIRED for M-chip deployment
# Generates default.metallib from all plant shader sources

set -e

SCRIPT_DIR="${0:A:h}"
SHADER_SRC="$SCRIPT_DIR/shaders/gaia_fusion_plants.metal"
OUTPUT_DIR="$SCRIPT_DIR/target/aarch64-apple-darwin/release"
METALLIB_PATH="$OUTPUT_DIR/default.metallib"

echo "═══════════════════════════════════════════════════════════════"
echo "GaiaFusion Metal Shader Precompilation"
echo "Apple Silicon (arm64) — All 9 Plant Types"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Verify shader source exists
if [[ ! -f "$SHADER_SRC" ]]; then
    echo "❌ ERROR: Shader source not found: $SHADER_SRC"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Step 1: Compile Metal source to AIR (Apple Intermediate Representation)
echo "▶ Compiling Metal source to AIR..."
AIR_FILE="$OUTPUT_DIR/gaia_fusion_plants.air"

xcrun -sdk macosx metal \
    -c "$SHADER_SRC" \
    -o "$AIR_FILE" \
    -std=metal3.0 \
    -target air64-apple-macos14.0

if [[ ! -f "$AIR_FILE" ]]; then
    echo "❌ ERROR: Metal compilation failed"
    exit 1
fi

echo "✓ AIR compilation complete: $AIR_FILE"

# Step 2: Link AIR to metallib
echo "▶ Linking AIR to default.metallib..."

xcrun -sdk macosx metallib \
    "$AIR_FILE" \
    -o "$METALLIB_PATH"

if [[ ! -f "$METALLIB_PATH" ]]; then
    echo "❌ ERROR: metallib linking failed"
    exit 1
fi

# Step 3: Verify metallib
METALLIB_SIZE=$(stat -f%z "$METALLIB_PATH")
echo "✓ default.metallib created: $METALLIB_SIZE bytes"

if [[ $METALLIB_SIZE -lt 1000 ]]; then
    echo "⚠️  WARNING: metallib suspiciously small ($METALLIB_SIZE bytes)"
fi

# Step 4: Copy to Resources directory for Swift Package
RESOURCES_DIR="$SCRIPT_DIR/../Resources"
mkdir -p "$RESOURCES_DIR"
cp "$METALLIB_PATH" "$RESOURCES_DIR/default.metallib"
echo "✓ Copied to Resources/default.metallib"

# Step 5: Clean up intermediate files
rm -f "$AIR_FILE"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ Metal shader precompilation COMPLETE"
echo "   default.metallib: $METALLIB_SIZE bytes"
echo "   Target: Apple Silicon arm64 / Metal 3.0 / macOS 14+"
echo "═══════════════════════════════════════════════════════════════"
