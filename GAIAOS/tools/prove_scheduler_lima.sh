#!/usr/bin/env bash
set -euo pipefail

LIMA_NAME="${LIMA_NAME:-default}"

# Deterministic paths (non-negotiable)
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/opt/gaiaos/workspace}"
STATUS_URL="${STATUS_URL:-http://127.0.0.1:8805/status}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8805/health}"

# Optional: if you want this script to start the service/container in Lima, set START_CMD
# Example:
# START_CMD='docker compose -f /opt/gaiaos/workspace/deploy/docker-compose.yml up -d gaiaos-game-runner'
START_CMD="${START_CMD:-}"

run_in_lima() {
  limactl shell "$LIMA_NAME" -- bash -lc "$*"
}

echo "== LIMA PROOF =="
echo "LIMA_NAME=$LIMA_NAME"
run_in_lima "uname -a && echo arch=\$(arch) && echo whoami=\$(whoami)"

# Runtime detection
run_in_lima '
set -e
if command -v docker >/dev/null 2>&1; then echo "runtime=docker"; exit 0; fi
if command -v nerdctl >/dev/null 2>&1; then echo "runtime=nerdctl"; exit 0; fi
echo "runtime=NONE"; exit 1
'

if [[ -n "$START_CMD" ]]; then
  echo "Starting service via START_CMD"
  run_in_lima "$START_CMD"
fi

# Ensure topology stub exists (fail-closed gate)
echo "Ensuring topology exists"
run_in_lima "WORKSPACE_ROOT='$WORKSPACE_ROOT' TOPOLOGY_PATH='$WORKSPACE_ROOT/ftcl/config/triad_topology.json' bash -lc '
mkdir -p \"$WORKSPACE_ROOT/ftcl/config\"
if [[ ! -f \"$WORKSPACE_ROOT/ftcl/config/triad_topology.json\" ]]; then
  cat > \"$WORKSPACE_ROOT/ftcl/config/triad_topology.json\" <<JSON
{ \"version\": \"v1\", \"cells\": [ { \"cell_id\": \"LIMA_VM\", \"role\": \"dev\", \"endpoints\": {} } ] }
JSON
fi
ls -lah \"$WORKSPACE_ROOT/ftcl/config/triad_topology.json\"
'"

echo "Curl /health"
run_in_lima "curl -fsS '$HEALTH_URL' | head -c 2000; echo"

echo "Curl /status #1"
S1="$(run_in_lima "curl -fsS '$STATUS_URL'")"
echo "$S1" | head -c 4000; echo

sleep 15

echo "Curl /status #2"
S2="$(run_in_lima "curl -fsS '$STATUS_URL'")"
echo "$S2" | head -c 4000; echo

# Extract tick_count without jq dependency
tick1="$(printf '%s' "$S1" | sed -n 's/.*"tick_count"[[:space:]]*:[[:space:]]*\([0-9]\+\).*/\1/p' | head -n1 || true)"
tick2="$(printf '%s' "$S2" | sed -n 's/.*"tick_count"[[:space:]]*:[[:space:]]*\([0-9]\+\).*/\1/p' | head -n1 || true)"

if [[ -z "$tick1" || -z "$tick2" ]]; then
  echo "FAIL: could not parse tick_count from /status"
  exit 1
fi

if (( tick2 <= tick1 )); then
  echo "FAIL: tick_count did not increase ($tick1 -> $tick2)"
  exit 1
fi

echo "OK: tick_count increased ($tick1 -> $tick2)"

# Write a proof bundle inside Lima workspace
DATE_UTC="$(date -u +%Y%m%d)"
PROOF_DIR="$WORKSPACE_ROOT/ftcl/runtime/runs/$DATE_UTC/proofs"
PROOF_PATH="$PROOF_DIR/lima_proof.json"

echo "Writing proof bundle to: $PROOF_PATH"
run_in_lima "bash -lc '
set -euo pipefail
mkdir -p \"$PROOF_DIR\"
cat > \"$PROOF_PATH\" <<JSON
{
  \"kind\": \"scheduler_lima_proof\",
  \"ts_utc\": \"$(date -u +%FT%TZ)\",
  \"lima_name\": \"$LIMA_NAME\",
  \"health_url\": \"$HEALTH_URL\",
  \"status_url\": \"$STATUS_URL\",
  \"tick1\": $tick1,
  \"tick2\": $tick2,
  \"status_1\": $(python3 - <<PY
import json,sys
s = """$S1"""
try:
  json.loads(s)
  print(json.dumps(json.loads(s)))
except Exception:
  print(json.dumps({\"raw\": s[:8000]}))
PY
),
  \"status_2\": $(python3 - <<PY
import json,sys
s = """$S2"""
try:
  json.loads(s)
  print(json.dumps(json.loads(s)))
except Exception:
  print(json.dumps({\"raw\": s[:8000]}))
PY
)
}
JSON
ls -lah \"$PROOF_PATH\"
'"

echo "DONE"
