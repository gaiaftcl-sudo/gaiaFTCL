#!/bin/bash
# Optional gateway probe; mesh gateway may not expose /vqbit/torsion — then prints NOHARM.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -a
# shellcheck source=/dev/null
[ -f "$DIR/phase6_gateway.env" ] && . "$DIR/phase6_gateway.env"
set +a
G="${GAIAFTCL_GATEWAY:-http://127.0.0.1:18803}"
if ! out="$(curl -sf "${G}/vqbit/torsion" 2>/dev/null)"; then
  echo "NOHARM"
  exit 0
fi
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("system_state","NOHARM"))' 2>/dev/null || echo "NOHARM"
