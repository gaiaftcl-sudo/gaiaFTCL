#!/usr/bin/env bash
# C4 witness: GaiaFusion (or UsdProbeCLI) binary must link USD_Core via @rpath and resolve on disk.
# SwiftPM places USD_Core.framework next to the executable under .build/.../debug|release — production .app
# bundles must copy the framework into Contents/Frameworks and preserve rpath (or re-link with @loader_path).
#
# Usage:
#   bash scripts/verify_gaiafusion_usd_runtime_link.sh [path/to/GaiaFusion|path/to/GaiaFusion.app]
# Default: swift build --show-bin-path for GaiaFusion in macos/GaiaFusion.
#
# Exit 0 = CALORIE (link line + framework path present); 1 = REFUSED
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/macos/GaiaFusion"

resolve_binary() {
  local arg="${1:-}"
  if [[ -z "$arg" ]]; then
    local bp
    bp="$(cd "$PKG" && swift build --show-bin-path)"
    echo "$bp/GaiaFusion"
    return 0
  fi
  if [[ "$arg" == *.app ]]; then
    echo "${arg%/}/Contents/MacOS/GaiaFusion"
    return 0
  fi
  echo "$arg"
}

ORIG_ARG="${1:-}"
APP_BUNDLE=""
if [[ -n "$ORIG_ARG" && "$ORIG_ARG" == *.app ]]; then
  APP_BUNDLE="${ORIG_ARG%/}"
  if [[ ! -d "$APP_BUNDLE/Contents/Frameworks/USD_Core.framework" ]]; then
    echo "REFUSED: USD_Core.framework missing from .app bundle (expected ${APP_BUNDLE}/Contents/Frameworks/USD_Core.framework)" >&2
    exit 1
  fi
fi

BIN="$(resolve_binary "${1:-}")"
if [[ ! -f "$BIN" || ! -x "$BIN" ]]; then
  echo "REFUSED: binary missing or not executable: $BIN" >&2
  exit 1
fi

# Packaged .app: SwiftPM's @loader_path rpath resolves to MacOS/; install_name_tool must add
# @executable_path/../Frameworks or dyld aborts at launch (USD_Core lives in Contents/Frameworks).
if [[ -n "$APP_BUNDLE" ]]; then
  if ! otool -l "$BIN" 2>/dev/null | rg -Fq "path @executable_path/../Frameworks"; then
    echo "REFUSED: $BIN missing LC_RPATH path @executable_path/../Frameworks (dyld will not find Contents/Frameworks/USD_Core)" >&2
    otool -l "$BIN" 2>/dev/null | rg -n "LC_RPATH|path " | head -30 >&2 || true
    exit 1
  fi
  PINFO="${APP_BUNDLE}/Contents/Frameworks/USD_Core.framework/Versions/A/usd/ar/resources/plugInfo.json"
  if [[ ! -f "$PINFO" ]]; then
    echo "REFUSED: USD plugin resources missing from bundle (ArDefaultResolver plugInfo): $PINFO" >&2
    exit 1
  fi
fi

if ! otool -L "$BIN" 2>/dev/null | grep -q '@rpath/USD_Core\.framework'; then
  echo "REFUSED: otool -L does not show @rpath/USD_Core.framework — $BIN" >&2
  otool -L "$BIN" >&2 || true
  exit 1
fi

BIN_DIR="$(dirname "$BIN")"
FW_CANDIDATES=(
  "$BIN_DIR/USD_Core.framework/Versions/A/USD_Core"
  "$BIN_DIR/../Frameworks/USD_Core.framework/Versions/A/USD_Core"
)
found=""
for f in "${FW_CANDIDATES[@]}"; do
  if [[ -f "$f" ]]; then
    found="$f"
    break
  fi
done

if [[ -z "$found" ]]; then
  echo "REFUSED: USD_Core binary not found beside executable or in ../Frameworks — expected one of:" >&2
  printf '  %s\n' "${FW_CANDIDATES[@]}" >&2
  exit 1
fi

echo "CALORIE: USD_Core runtime resolvable — binary=$BIN framework_slice=$found"
exit 0
