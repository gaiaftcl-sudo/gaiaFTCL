#!/usr/bin/env zsh
# One-command Franklin GAMP5 proof for what exists today: Swift (admin-cell) + receipt v1 conformance.
# Optional E2E: set RUN_FRANKLIN_E2E=1 to run the zero-human Franklin script and validate the latest receipt.
# Usage: from repo root — zsh cells/franklin/scripts/franklin_gamp5_validate.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRANKLIN="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO="$(cd "$FRANKLIN/../.." && pwd)"
AC="$REPO/cells/health/swift/AdminCellRunner"
CONF_TEST="$FRANKLIN/tests/test_franklin_receipt_conformance.sh"

if [[ ! -d "$AC" ]]; then
  echo "REFUSED: missing AdminCellRunner at $AC" >&2
  exit 1
fi
if [[ ! -f "$CONF_TEST" ]]; then
  echo "REFUSED: missing $CONF_TEST" >&2
  exit 1
fi

echo "== Franklin GAMP5 validate (repo: $REPO)"
echo "== 1) Swift: AdminCellRunner (swift test)"
( cd "$AC" && swift test )

echo "== 1b) Mac mesh cell + shared vQbit doc contract (IMPLEMENTATION_PLAN.md)"
( cd "$REPO" && zsh "$FRANKLIN/tests/test_mac_mesh_cell_narrative_lock.sh" )

echo "== 2) F0 pin integrity (cells/franklin/pins.json + admin-cell expected hash file)"
PINS_J="$FRANKLIN/pins.json"
if [[ -f "$PINS_J" ]]; then
  # shellcheck source=/dev/null
  source "$FRANKLIN/scripts/_franklin_bin.zsh"
  if ! franklin_require_bin; then
    exit 1
  fi
  if ! "$FRANKLIN_BIN" verify-pins --repo "$REPO"; then
    echo "pin verify failed (run: zsh cells/franklin/scripts/refresh_franklin_pins.sh from repo to record current SHAs)" >&2
    exit 1
  fi
else
  echo "skip: no $PINS_J"
fi

echo "== 3) Shell: receipt v1 conformance (fixture + negative test; optional E2E via RUN_FRANKLIN_E2E=1)"
( cd "$REPO" && zsh "$CONF_TEST" )

echo "== 4) Evidence: audit_trail_verify (all franklin v1 receipts in cells/health/evidence/)"
( cd "$REPO" && zsh "$FRANKLIN/scripts/audit_trail_verify.sh" )

echo "== Franklin GAMP5 validate: OK"
