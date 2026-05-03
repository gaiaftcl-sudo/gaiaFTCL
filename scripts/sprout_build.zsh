#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRANKLIN_DIR="$ROOT/GAIAOS/macos/Franklin"
WORKSPACE="$ROOT/cells/xcode/GaiaComposite.xcworkspace"
BUILD_DIR="$ROOT/build"
REALITY_ASSET_SCRIPT="$ROOT/scripts/compile_franklin_reality_assets.sh"
ASSET_GATE_SCRIPT="$ROOT/scripts/check_franklin_avatar_assets.zsh"
PASSY_GATE_SCRIPT="$ROOT/scripts/require_franklin_passy_assets.sh"

usage() {
  cat <<'EOF'
Usage: scripts/sprout_build.zsh [options]

Options:
  --with-xcodebuild      Attempt xcodebuild clean/build + tests for Franklin scheme.
  --with-usd-audit       Run usdchecker/usdtree/usdcat if available.
  --with-metal           Compile Franklin_Z3.metal if source exists.
  --with-xctrace         Capture short Power Profiler trace if app is running.
  --no-open              Do not open Xcode workspace at end.
  --help                 Show this help.

Default flow (always):
  1) repo health gate
  2) Franklin asset gates
  3) Franklin Swift tests
  4) Franklin reality asset compile
  5) Franklin programming step
EOF
}

WITH_XCODEBUILD=0
WITH_USD_AUDIT=0
WITH_METAL=0
WITH_XCTRACE=0
NO_OPEN=0

for arg in "$@"; do
  case "$arg" in
    --with-xcodebuild) WITH_XCODEBUILD=1 ;;
    --with-usd-audit) WITH_USD_AUDIT=1 ;;
    --with-metal) WITH_METAL=1 ;;
    --with-xctrace) WITH_XCTRACE=1 ;;
    --no-open) NO_OPEN=1 ;;
    --help) usage; exit 0 ;;
    *)
      echo "REFUSED: unknown option: $arg" >&2
      usage
      exit 2
      ;;
  esac
done

cd "$ROOT"
mkdir -p "$BUILD_DIR"

echo "==> [1/6] repo health gate"
"$ROOT/scripts/repo_health_gate.sh"

echo "==> [2/6] Franklin hard asset gates"
"$PASSY_GATE_SCRIPT" "$ROOT"
"$ASSET_GATE_SCRIPT" "$ROOT"

echo "==> [3/6] Franklin swift tests"
swift test --package-path "$FRANKLIN_DIR"

echo "==> [4/6] Franklin reality asset compile"
"$REALITY_ASSET_SCRIPT" "$ROOT"

if (( WITH_XCODEBUILD )); then
  echo "==> [5/6] xcodebuild Franklin (optional)"
  if command -v xcodebuild >/dev/null 2>&1; then
    if [[ -d "$WORKSPACE" ]] && xcodebuild -workspace "$WORKSPACE" -list 2>/dev/null | rg -n "Franklin" >/dev/null 2>&1; then
      xcodebuild clean build -workspace "$WORKSPACE" -scheme Franklin -destination "platform=macOS" ENABLE_USER_SCRIPT_SANDBOXING=NO
      xcodebuild test -workspace "$WORKSPACE" -scheme Franklin -destination "platform=macOS"
    else
      echo "WARN: Franklin scheme not found in composite workspace; skipping xcodebuild."
    fi
  else
    echo "WARN: xcodebuild unavailable; skipping."
  fi
fi

if (( WITH_USD_AUDIT )); then
  echo "==> [optional] USD audit"
  USDZ="$ROOT/cells/franklin/avatar/bundle_assets/meshes/Franklin_Passy_V2.usdz"
  if [[ -f "$USDZ" ]]; then
    command -v usdchecker >/dev/null 2>&1 && usdchecker "$USDZ" || true
    command -v usdtree >/dev/null 2>&1 && usdtree "$USDZ" > "$BUILD_DIR/Franklin_Passy_V2.tree.txt" || true
    command -v usdcat >/dev/null 2>&1 && usdcat "$USDZ" --out "$BUILD_DIR/Franklin_Check.usda" || true
  else
    echo "WARN: missing USDZ at $USDZ; skipping USD audit."
  fi
fi

if (( WITH_METAL )); then
  echo "==> [optional] Metal shader compile"
  SHADER="$ROOT/cells/franklin/avatar/bundle_assets/materials/Franklin_Z3.metal"
  AIR="$BUILD_DIR/Franklin_Z3.air"
  OUT_LIB="$ROOT/cells/franklin/avatar/bundle_assets/materials/Franklin_Z3_Materials.metallib"
  if [[ -f "$SHADER" ]]; then
    xcrun -sdk macosx metal -c "$SHADER" -o "$AIR"
    xcrun -sdk macosx metallib "$AIR" -o "$OUT_LIB"
  else
    echo "WARN: missing shader source $SHADER; skipping Metal compile."
  fi
fi

if (( WITH_XCTRACE )); then
  echo "==> [optional] xctrace capture"
  if xcrun --find xctrace >/dev/null 2>&1; then
    if pgrep -x Franklin >/dev/null 2>&1; then
      xcrun xctrace record --template "Power Profiler" --attach Franklin --time-limit 10s --output "$BUILD_DIR/franklin_power.trace" >/dev/null 2>&1 || true
    else
      echo "WARN: Franklin app not running; skipping xctrace attach."
    fi
  else
    echo "WARN: xctrace not found; skipping."
  fi
fi

echo "==> [6/6] Franklin programming and workspace open"
"$ROOT/scripts/program_franklin_app.zsh"

if (( ! NO_OPEN )); then
  if [[ -d "$WORKSPACE" ]]; then
    open "$WORKSPACE"
  else
    echo "WARN: composite workspace not found at $WORKSPACE."
  fi
fi

echo "PASS: sprout build workflow complete"
