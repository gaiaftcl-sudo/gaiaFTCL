#!/usr/bin/env bash
# Run run_fusion_mac_app_gate.py against a packaged GaiaFusion.app (no swift build, no composite rebuild).
# Default bundle: GAIAFUSION_APP_PATH or /tmp/gaiafusion-delivery/GaiaFusion.app (package_gaiafusion_app.sh staging).
#
# Run from **Terminal.app** on the Mac (not a restricted automation host) so the GUI process can bind LocalServer
# and WKWebView can answer `/api/fusion/self-probe`.
#
# Optional env:
#   GAIAFUSION_GATE_OPENUSD_HEADLESS_OK=1 — when Metal `frames_presented` stays 0 (no visible display session),
#     gate still passes OpenUSD if `stage_loaded` + `render_path` match (strict default: frames_presented > 0).
#
# Usage:
#   bash scripts/run_gaiafusion_gate_packaged.sh
#   GAIAFUSION_GATE_APP_BUNDLE=/Volumes/GaiaFusion/GaiaFusion.app bash scripts/run_gaiafusion_gate_packaged.sh
#   GAIAFUSION_GATE_OPENUSD_HEADLESS_OK=1 bash scripts/run_gaiafusion_gate_packaged.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${GAIAFUSION_GATE_APP_BUNDLE:-${GAIAFUSION_APP_PATH:-/tmp/gaiafusion-delivery/GaiaFusion.app}}"
export GAIAFUSION_GATE_APP_BUNDLE="$APP"
export GAIAFUSION_GATE_SKIP_SWIFT_BUILD=1
cd "$ROOT"
exec python3 scripts/run_fusion_mac_app_gate.py --skip-composite-assets --skip-playwright "$@"
