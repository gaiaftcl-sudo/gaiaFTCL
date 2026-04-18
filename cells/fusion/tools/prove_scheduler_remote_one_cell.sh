#!/usr/bin/env bash
set -euo pipefail

CELL_HOST="${CELL_HOST:?Set CELL_HOST (ip or host)}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"

# Deterministic paths (non-negotiable)
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/opt/gaiaos/workspace}"
STATUS_URL="${STATUS_URL:-http://127.0.0.1:8805/status}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8805/health}"

ssh_cmd() {
  ssh -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${CELL_HOST}" "$@"
}

echo "== REMOTE CELL PROOF =="
echo "CELL_HOST=$CELL_HOST SSH_USER=$SSH_USER SSH_PORT=$SSH_PORT"
ssh_cmd "uname -a && echo arch=\$(arch) && echo whoami=\$(whoami)"

echo "Ensuring topology exists on remote"
ssh_cmd "bash -lc '
set -euo pipefail
mkdir -p \"$WORKSPACE_ROOT/ftcl/config\"
if [[ ! -f \"$WORKSPACE_ROOT/ftcl/config/triad_topology.json\" ]]; then
  cat > \"$WORKSPACE_ROOT/ftcl/config/triad_topology.json\" <<JSON
{ \"version\": \"v1\", \"cells\": [ { \"cell_id\": \"REMOTE_$CELL_HOST\", \"role\": \"cell\", \"endpoints\": {} } ] }
JSON
fi
ls -lah \"$WORKSPACE_ROOT/ftcl/config/triad_topology.json\"
'"

echo "Curl /health (remote localhost)"
ssh_cmd "bash -lc 'curl -fsS \"$HEALTH_URL\" | head -c 2000; echo'"

echo "Curl /status #1"
S1="$(ssh_cmd "bash -lc 'curl -fsS \"$STATUS_URL\"'")"
echo "$S1" | head -c 4000; echo

sleep 15

echo "Curl /status #2"
S2="$(ssh_cmd "bash -lc 'curl -fsS \"$STATUS_URL\"'")"
echo "$S2" | head -c 4000; echo

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

# Capture logs (best-effort). Adjust unit/container names as needed.
echo "Capturing recent logs (best-effort)"
LOGS="$(ssh_cmd "bash -lc '
set -e
( systemctl status gaiaos-game-runner --no-pager 2>/dev/null || true )
echo \"---\"
( journalctl -u gaiaos-game-runner -n 120 --no-pager 2>/dev/null || true )
echo \"---\"
( docker ps 2>/dev/null | head -n 50 || true )
echo \"---\"
( docker logs --tail 120 gaiaos-game-runner 2>/dev/null || true )
'")"
echo "$LOGS" | head -c 8000; echo

DATE_UTC="$(date -u +%Y%m%d)"
PROOF_DIR="$WORKSPACE_ROOT/ftcl/runtime/runs/$DATE_UTC/proofs"
PROOF_PATH="$PROOF_DIR/remote_proof_${CELL_HOST}.json"

echo "Writing proof bundle to: $PROOF_PATH"
ssh_cmd "bash -lc '
set -euo pipefail
mkdir -p \"$PROOF_DIR\"
python3 - <<PY
import json, time
proof = {
  \"kind\": \"scheduler_remote_proof\",
  \"ts_utc\": time.strftime(\"%Y-%m-%dT%H:%M:%SZ\", time.gmtime()),
  \"cell_host\": \"$CELL_HOST\",
  \"health_url\": \"$HEALTH_URL\",
  \"status_url\": \"$STATUS_URL\",
  \"tick1\": $tick1,
  \"tick2\": $tick2,
  \"status_1\": None,
  \"status_2\": None,
  \"logs_excerpt\": None
}
s1 = '''$S1'''
s2 = '''$S2'''
logs = '''$LOGS'''
def parse(s):
  try:
    return json.loads(s)
  except Exception:
    return {\"raw\": s[:8000]}
proof[\"status_1\"] = parse(s1)
proof[\"status_2\"] = parse(s2)
proof[\"logs_excerpt\"] = logs[:8000]
open(\"$PROOF_PATH\",\"w\").write(json.dumps(proof, indent=2))
print(\"wrote\", \"$PROOF_PATH\")
PY
ls -lah \"$PROOF_PATH\"
'"

echo "DONE"
