#!/usr/bin/env zsh
# IQ (installation) validation — build Rust FFI + GaiaFusion (matches mac-cell-ci pattern).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}"

cd "$ROOT/MetalRenderer"
rustup target add aarch64-apple-darwin 2>/dev/null || true
cargo build --release --target aarch64-apple-darwin
mkdir -p lib
cp target/aarch64-apple-darwin/release/libgaia_metal_renderer.a lib/

cd "$ROOT"
xcodebuild build \
  -scheme GaiaFusion \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED"

echo "run_iq_validation: OK"
