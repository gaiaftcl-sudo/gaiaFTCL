#!/usr/bin/env bash
# Run on a host that shares gaiaftcl_gaiaftcl with gaiaftcl-sovereign-ui (e.g. from another mesh container).
# Usage: SOVEREIGN_UI_URL=http://gaiaftcl-sovereign-ui:3000 ./scripts/verify_sovereign_ui_panels.sh
set -euo pipefail
BASE="${SOVEREIGN_UI_URL:-http://gaiaftcl-sovereign-ui:3000}"
JSON="$(python3 -c "import urllib.request; print(urllib.request.urlopen('${BASE}/api/sovereign-mesh', timeout=120).read().decode())")"
RW="$(echo "$JSON" | python3 -c "import sys,json; j=json.load(sys.stdin); print(json.dumps(j.get('panels',{}).get('receipt_wall',[])))" 2>/dev/null || echo "")"
DISC="$(echo "$JSON" | python3 -c "import sys,json; j=json.load(sys.stdin); print(json.dumps(j.get('panels',{}).get('discovery_manifest',[])))" 2>/dev/null || echo "")"
OWL="$(echo "$JSON" | python3 -c "import sys,json; j=json.load(sys.stdin); print(json.dumps(j.get('panels',{}).get('game_room_feeds',{}).get('owl_protocol',[])))" 2>/dev/null || echo "")"

fail=0
check() {
  local name="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "OK  $name (found: $needle)"
  else
    echo "FAIL $name (missing: $needle)"
    fail=$((fail + 1))
  fi
}

echo "GET $BASE/api/sovereign-mesh"
check "Panel 1 receipt timestamp" "$RW" "20260327T124650Z"
check "Panel 2 LEUK-005" "$DISC" "LEUK-005"
check "Panel 2 AML-CHEM-001" "$DISC" "AML-CHEM-001"
check "Panel 4 owl janowitz" "$OWL" "janowitz"
check "Panel 5 healthy" "$JSON" "\"status\":\"healthy\""
echo "---"
if [[ "$fail" -ne 0 ]]; then
  echo "VERIFY FAILED: $fail check(s)"
  exit 1
fi
echo "All verification substrings matched."
