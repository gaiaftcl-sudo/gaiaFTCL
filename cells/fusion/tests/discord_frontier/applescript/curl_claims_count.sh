#!/bin/bash
# Prints number of claims returned (for heartbeat). Sources phase6_gateway.env next to this script.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -a
# shellcheck source=/dev/null
[ -f "$DIR/phase6_gateway.env" ] && . "$DIR/phase6_gateway.env"
set +a
G="${GAIAFTCL_GATEWAY:-http://127.0.0.1:18803}"
KEY="${GAIAFTCL_INTERNAL_KEY:-}"
FILTER="${1:-CALORIE}"
LIM="${2:-5}"
enc="$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$FILTER'''))")"
url="${G}/claims?filter=${enc}&limit=${LIM}"
if [[ -n "$KEY" ]]; then
  if ! out="$(curl -sf "$url" -H "X-Gaiaftcl-Internal-Key: ${KEY}" 2>/dev/null)"; then
    echo 0
    exit 0
  fi
else
  if ! out="$(curl -sf "$url" 2>/dev/null)"; then
    echo 0
    exit 0
  fi
fi
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)'
