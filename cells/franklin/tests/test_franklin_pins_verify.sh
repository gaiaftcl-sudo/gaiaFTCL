#!/usr/bin/env zsh
# F0: ensure orchestrator + Franklin GAMP5 script bytes match cells/franklin/pins.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/_franklin_bin.zsh"
franklin_require_bin
exec "$FRANKLIN_BIN" verify-pins --repo "$REPO"
