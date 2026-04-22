#!/usr/bin/env zsh
# Full Mac Franklin pack: GAMP5 validate (Swift + doc lock + pins + receipt + evidence) +
#   fo_cell_substrate release (fo-franklin for pins / receipts) + MacFranklin.app build.
# Usage: from repo root:
#   zsh cells/franklin/scripts/franklin_mac_full_package_validate.sh
# Optional: RUN_FRANKLIN_E2E=1 is passed through to the inner GAMP5 validate (via nothing here—set env when running receipt test separately if needed).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRANKLIN="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO="$(cd "$FRANKLIN/../.." && pwd)"
FO_SUB="$REPO/cells/shared/rust/fo_cell_substrate"
MACF="$REPO/cells/health/swift/MacFranklin"

echo "== Franklin Mac full package + validate (repo: $REPO)"
echo "== 1) GAMP5 validate (narrative lock, swift test, pins, receipt conformance, evidence audit)"
( cd "$REPO" && zsh "$FRANKLIN/scripts/franklin_gamp5_validate.sh" )

if [[ -d "$FO_SUB" ]]; then
  echo "== 2) fo_cell_substrate release (fo-franklin, fo-health, fo-fusion)"
  ( cd "$FO_SUB" && cargo build -p fo_cell_substrate --release )
else
  echo "== 2) skip: no $FO_SUB" >&2
fi

if [[ -d "$MACF" && -f "$MACF/build_macfranklin_app.sh" ]]; then
  echo "== 3) MacFranklin.app bundle (SwiftPM release)"
  ( zsh "$MACF/build_macfranklin_app.sh" )
else
  echo "== 3) skip: MacFranklin at $MACF" >&2
fi

echo "== Franklin Mac full package + validate: OK"
