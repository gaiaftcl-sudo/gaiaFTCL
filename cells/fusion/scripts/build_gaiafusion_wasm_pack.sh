#!/usr/bin/env bash
# Single wasm-pack invocation for services/atc_physics_wasm → Resources/gaiafusion_substrate.wasm
# If wasm-pack or build fails, writes committed spike bytes (minimal valid module) so SwiftPM still bundles.
set -euo pipefail

# Prefer rustup/Cargo toolchain over Homebrew `rustc` so `wasm32-unknown-unknown` resolves (wasm-pack uses active rustc).
export PATH="${HOME}/.cargo/bin:${PATH}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRATE="$ROOT/services/atc_physics_wasm"
DEST="$ROOT/macos/GaiaFusion/GaiaFusion/Resources/gaiafusion_substrate.wasm"
DEST_JS="$ROOT/macos/GaiaFusion/GaiaFusion/Resources/gaiafusion_substrate_bindgen.js"
# Minimal valid wasm (empty func) — same as Phase A spike; WebAssembly.validate passes in V8/WebKit.
SPIKE_HEX="0061736d01000000010401600000030201000a040102000b"
LOG_LABEL="[build_gaiafusion_wasm_pack]"

write_spike() {
  python3 -c "import pathlib; pathlib.Path('$DEST').write_bytes(bytes.fromhex('$SPIKE_HEX'))"
  rm -f "$DEST_JS"
}

if [[ ! -d "$CRATE" ]]; then
  echo "$LOG_LABEL REFUSED: missing $CRATE" >&2
  write_spike
  exit 1
fi

if ! command -v wasm-pack >/dev/null 2>&1; then
  echo "$LOG_LABEL wasm-pack not in PATH — writing minimal spike wasm to $DEST"
  write_spike
  exit 0
fi

cd "$CRATE"
export RUSTFLAGS="${RUSTFLAGS:-}"
if ! rustup target list --installed 2>/dev/null | grep -q wasm32-unknown-unknown; then
  echo "$LOG_LABEL installing wasm32-unknown-unknown"
  rustup target add wasm32-unknown-unknown 2>/dev/null || true
fi

PKG_DIR="$CRATE/pkg_gaiafusion"
rm -rf "$PKG_DIR"
if wasm-pack build --target web --release --out-dir "$PKG_DIR" 2>/tmp/gaiafusion_wasm_pack.err; then
  BG=$(ls "$PKG_DIR"/*_bg.wasm 2>/dev/null | head -1)
  JS="$PKG_DIR/atc_physics_wasm.js"
  if [[ -f "$BG" && -f "$JS" ]]; then
    cp -f "$BG" "$DEST"
    cp -f "$JS" "$DEST_JS"
    rm -rf "$PKG_DIR"
    echo "$LOG_LABEL CALORIE: gaiafusion_substrate.wasm + gaiafusion_substrate_bindgen.js ($(wc -c <"$DEST") + $(wc -c <"$DEST_JS") bytes)"
    exit 0
  fi
fi
echo "$LOG_LABEL wasm-pack build failed — spike fallback (see /tmp/gaiafusion_wasm_pack.err tail)" >&2
tail -20 /tmp/gaiafusion_wasm_pack.err 2>/dev/null || true
write_spike
exit 0
