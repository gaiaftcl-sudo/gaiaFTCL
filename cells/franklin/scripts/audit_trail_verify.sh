#!/usr/bin/env zsh
# F0: Walk evidence; validate every franklin_mac_admin_gamp5_*.json (v1 schema) and bootstrap receipts.
set -euo pipefail
FRANKLIN="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$FRANKLIN/../.." && pwd)"
# shellcheck source=/dev/null
source "$FRANKLIN/scripts/_franklin_bin.zsh"
if ! franklin_require_bin; then
  exit 1
fi
exec "$FRANKLIN_BIN" audit-trail --repo "$REPO"
