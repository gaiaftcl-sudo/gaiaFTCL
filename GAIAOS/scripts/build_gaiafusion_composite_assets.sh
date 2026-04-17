#!/usr/bin/env bash
# Build all GaiaFusion-embedded assets: precompiled Metal + mirrored fusion-web (Next standalone HTML + _next/static + public).
# Run from repo root before swift/xcodebuild so Package `.process("Resources")` bundles them into the composite Mac app.
# Packaged .app + DMG (embed USD_Core.framework, codesign, otool verify): scripts/package_gaiafusion_app.sh — invoked from build_gaiafusion_release.sh when GAIAFUSION_PACKAGE_APP=1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI="$ROOT/services/gaiaos_ui_web"
DEST="$ROOT/macos/GaiaFusion/GaiaFusion/Resources/fusion-web"
STAND="$UI/.next/standalone"
LOG_LABEL="[build_gaiafusion_composite_assets]"

echo "$LOG_LABEL ROOT=$ROOT"

bash "$ROOT/scripts/build_gaiafusion_metal_lib.sh"
bash "$ROOT/scripts/generate_gaiafusion_branding_assets.sh"
bash "$ROOT/scripts/build_gaiafusion_wasm_pack.sh"

if [[ ! -f "$UI/package.json" ]]; then
  echo "$LOG_LABEL REFUSED: missing $UI/package.json"
  exit 1
fi

cd "$UI"
if [[ ! -d node_modules ]]; then
  echo "$LOG_LABEL npm ci (no node_modules)"
  npm ci
fi

# APFS/npm artifact duplicates: empty dirs under @types named like `d3-array 2` make TypeScript
# treat `d3-array 2` as an implicit types package and fail `next build`. Remove them before tsc.
TYPES_DIR="$UI/node_modules/@types"
if [[ -d "$TYPES_DIR" ]]; then
  while IFS= read -r _dup; do
    [[ -z "$_dup" ]] && continue
    rm -rf "$_dup"
    echo "$LOG_LABEL removed corrupt @types duplicate: $_dup"
  done < <(find "$TYPES_DIR" -maxdepth 1 -name '* 2' 2>/dev/null || true)
fi

echo "[10] Validating UUM-8D Epistemic Dictionary..."
if ! npm run test:unit:fusion; then
  echo "REFUSED: 11-locale invariant broken. Halting composite bake."
  exit 1
fi

echo "$LOG_LABEL next build (standalone)"
# Next occasionally fails with ENOTEMPTY rmdir '.next/server' when a prior build left a partial tree.
rm -rf "$UI/.next"
npm run build

# Pin Docker **cell** stack (MCP gateway/tester) into GaiaFusion bundle — Fusion itself stays native Swift; compose is for guest/full GAIAOS.
SIDECAR_CELL="$ROOT/macos/GaiaFusion/GaiaFusion/Resources/fusion-sidecar-cell"
mkdir -p "$SIDECAR_CELL/fusion_sidecar_guest"
cp -f "$ROOT/docker-compose.fusion-sidecar.yml" "$SIDECAR_CELL/"
cp -f "$ROOT/deploy/mac_cell_mount/README_CELL_STACK.md" "$SIDECAR_CELL/README_CELL_STACK.md"
cp -f "$ROOT/deploy/mac_cell_mount/fusion_sidecar_guest/README.md" "$SIDECAR_CELL/fusion_sidecar_guest/"
cp -f "$ROOT/deploy/mac_cell_mount/fusion_sidecar_guest/fusion-sidecar-compose.service" "$SIDECAR_CELL/fusion_sidecar_guest/"
echo "$LOG_LABEL refreshed fusion-sidecar-cell resources (MCP cell compose + guest hints)"

SPEC_NATIVE="$ROOT/macos/GaiaFusion/GaiaFusion/Resources/spec/native_fusion"
mkdir -p "$SPEC_NATIVE"
cp -f "$ROOT/spec/native_fusion/plant_adapters.json" "$SPEC_NATIVE/"
echo "$LOG_LABEL refreshed spec/native_fusion/plant_adapters.json (GF-REQ-MAC-CELL / GF-REQ-SWAP)"

if [[ ! -f "$STAND/server.js" ]]; then
  echo "$LOG_LABEL REFUSED: $STAND/server.js missing after next build"
  exit 1
fi

# Standalone runtime expects static assets next to server (Next docs).
mkdir -p "$STAND/.next"
rm -rf "$STAND/.next/static" "$STAND/public"
cp -R "$UI/.next/static" "$STAND/.next/static"
if [[ -d "$UI/public" ]]; then
  cp -R "$UI/public" "$STAND/public"
fi

PORT="$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")"
export HOSTNAME=127.0.0.1
export PORT
export NODE_ENV=production

echo "$LOG_LABEL ephemeral Next standalone on 127.0.0.1:$PORT (pack fusion-web)"

cleanup() {
  if [[ -n "${SRV_PID:-}" ]] && kill -0 "$SRV_PID" 2>/dev/null; then
    kill "$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

(
  cd "$STAND"
  exec node server.js
) &
SRV_PID=$!
sleep 0.4

ready=0
for _ in $(seq 1 90); do
  if curl -sfS -m 2 "http://127.0.0.1:${PORT}/fusion-s4" -o /dev/null; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "$ready" != "1" ]]; then
  echo "$LOG_LABEL REFUSED: Next standalone did not serve /fusion-s4 in time"
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"

curl -sfS -m 60 "http://127.0.0.1:${PORT}/fusion-s4" -o "$DEST/index.html"
curl -sfS -m 60 "http://127.0.0.1:${PORT}/substrate" -o "$DEST/substrate.html"
curl -sfS -m 60 "http://127.0.0.1:${PORT}/substrate-raw" -o "$DEST/substrate-raw.html"

# Same chunk files the HTML references (hashed under .next/static).
mkdir -p "$DEST/_next/static"
cp -R "$UI/.next/static/"* "$DEST/_next/static/"

if [[ -d "$UI/public" ]]; then
  cp -R "$UI/public/." "$DEST/"
fi

if [[ ! -s "$DEST/index.html" ]]; then
  echo "$LOG_LABEL REFUSED: fusion-web/index.html empty or missing"
  exit 1
fi

echo "$LOG_LABEL CALORIE: $DEST (index.html + substrate + _next/static + public)"
ls -la "$DEST" | head -20
