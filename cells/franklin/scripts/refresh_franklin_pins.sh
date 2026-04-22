#!/usr/bin/env zsh
# F0: Record SHA-256 of scripts Franklin/admin-cell invoke. Writes:
#   - cells/franklin/pins.json
#   - cells/health/.admincell-expected/orchestrator.sha256 (64-char hex, one line) for existing admin-cell hash check
# Run from repo root or anywhere; idempotent. Implementation: fo-franklin (Rust fo_cell_substrate).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
H="${REPO}/cells/health/scripts/health_full_local_iqoqpq_gamp.sh"
F="${REPO}/cells/health/scripts/franklin_mac_admin_gamp5_zero_human.sh"
for p in "$H" "$F"; do
  if [[ ! -f "$p" ]]; then
    echo "REFUSED: missing $p" >&2
    exit 1
  fi
done
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_franklin_bin.zsh"
franklin_require_bin
exec "$FRANKLIN_BIN" refresh-pins --repo "$REPO"
