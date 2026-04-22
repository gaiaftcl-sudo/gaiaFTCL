#!/usr/bin/env zsh
# Doc contract: IMPLEMENTATION_PLAN must state Franklin as Mac admin cell, shared vQbit, Klein network anchor, one Franklin per Mac.
set -euo pipefail
ROOT="$(cd "${0:a:h}/../../.." && pwd)"
PLAN="${ROOT}/cells/franklin/IMPLEMENTATION_PLAN.md"
if [[ ! -f "$PLAN" ]]; then
  echo "REFUSED: missing $PLAN" >&2
  exit 1
fi
if ! /usr/bin/grep -q "Mac admin" "$PLAN" 2>/dev/null; then
  echo "REFUSED: IMPLEMENTATION_PLAN must state Mac admin cell framing" >&2
  exit 2
fi
if ! /usr/bin/grep -q "shared vQbit" "$PLAN" 2>/dev/null; then
  echo "REFUSED: IMPLEMENTATION_PLAN must state shared vQbit / substrate" >&2
  exit 3
fi
if ! /usr/bin/grep -q "Klein" "$PLAN" 2>/dev/null; then
  echo "REFUSED: IMPLEMENTATION_PLAN must reference Klein bottle / network graph language" >&2
  exit 4
fi
if ! /usr/bin/grep -q "every Mac" "$PLAN" 2>/dev/null; then
  echo "REFUSED: IMPLEMENTATION_PLAN must state one Franklin per Mac" >&2
  exit 5
fi
echo "OK: Mac mesh cell + shared vQbit narrative lock (IMPLEMENTATION_PLAN.md)"
exit 0
