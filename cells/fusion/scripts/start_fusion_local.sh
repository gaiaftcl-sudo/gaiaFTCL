#!/usr/bin/env bash
# Start Fusion UI dev server (same entry as invariant self-heal). For Popen / manual use.
# Bound to GaiaFusion dev-proxy port (default 3000), not the local server port (8910).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
export FUSION_UI_PORT="${FUSION_UI_PORT:-3000}"
export FUSION_UI_PROXY_PORT="${FUSION_UI_PROXY_PORT:-$FUSION_UI_PORT}"
cd "$ROOT/services/gaiaos_ui_web"
exec npm run dev:fusion
