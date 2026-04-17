#!/usr/bin/env bash
# Native USD load witness: builds and runs UsdPxrBridge-only CLI (no full GaiaFusion app).
# Requires: GAIAOS/macos/GaiaFusion, Internal/Frameworks/USD_Core_Framework.xcframework
# Usage: bash scripts/run_usd_probe_cli.sh
# Some sandboxes SIGKILL the binary (rc 137); use release smoke env GAIAFUSION_SKIP_USD_PROBE_CLI or
# GAIAFUSION_USD_PROBE_SIGKILL_OK for an honest PARTIAL receipt, or run on a full Mac.
# Exit 0 when pxr in-memory stage probe returns 1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/macos/GaiaFusion"
cd "$PKG"
swift build --product UsdProbeCLI
BIN="$(swift build --show-bin-path)"
export DYLD_FRAMEWORK_PATH="$BIN"
exec "$BIN/UsdProbeCLI"
