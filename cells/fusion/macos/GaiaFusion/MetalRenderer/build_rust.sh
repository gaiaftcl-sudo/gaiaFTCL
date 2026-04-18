#!/usr/bin/env zsh
set -e

SCRIPT_DIR="${0:A:h}"
RUST_DIR="$SCRIPT_DIR/rust"
TARGET_DIR="$RUST_DIR/target"

# Gap #4 Fix: Explicit Apple Silicon target
CARGO_TARGET="aarch64-apple-darwin"
BUILD_MODE="${1:-release}"

cd "$RUST_DIR"

if [[ "$BUILD_MODE" == "debug" ]]; then
    cargo build --target "$CARGO_TARGET"
    LIB_PATH="$TARGET_DIR/$CARGO_TARGET/debug/libgaia_metal_renderer.a"
else
    cargo build --release --target "$CARGO_TARGET"
    LIB_PATH="$TARGET_DIR/$CARGO_TARGET/release/libgaia_metal_renderer.a"
fi

# Gap #7: cbindgen runs automatically via build.rs
# Header is now at ../include/gaia_metal_renderer.h

# Copy static lib to a stable location SPM can find
mkdir -p "$SCRIPT_DIR/lib"
cp "$LIB_PATH" "$SCRIPT_DIR/lib/libgaia_metal_renderer.a"

echo "Rust library built: $SCRIPT_DIR/lib/libgaia_metal_renderer.a"
echo "C header generated: $SCRIPT_DIR/include/gaia_metal_renderer.h"
