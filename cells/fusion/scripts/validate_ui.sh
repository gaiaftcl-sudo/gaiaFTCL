#!/bin/bash
# GaiaFTCL UI — one-command validation (closed MCP surface)
# - gaiaos_ui_tester_mcp on 8900 (substrate default)
# - fot_mcp_gateway ingress on 8803 (MCP_BASE_URL for Playwright / Next proxies)
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TESTER_PORT="${MCP_TESTER_PORT:-8900}"
GATEWAY_PORT="${MCP_GATEWAY_PORT:-8803}"
TESTER_URL="http://127.0.0.1:${TESTER_PORT}"
GATEWAY_URL="http://127.0.0.1:${GATEWAY_PORT}"
export MCP_UI_TESTER_UPSTREAM="${MCP_UI_TESTER_UPSTREAM:-${TESTER_URL}}"

port_listening() {
  local host="$1" port="$2"
  if command -v nc &>/dev/null; then
    nc -z "$host" "$port" 2>/dev/null
  else
    return 1
  fi
}

wait_port() {
  local host="$1" port="$2" label="$3" max="${4:-30}"
  local i
  for i in $(seq 1 "$max"); do
    if port_listening "$host" "$port"; then
      echo "[validate_ui] $label ready on $host:$port"
      return 0
    fi
    sleep 0.5
  done
  return 1
}

# --- Tester (8900) ---
if port_listening 127.0.0.1 "$TESTER_PORT"; then
  echo "[validate_ui] gaiaos_ui_tester_mcp already on $TESTER_PORT, reusing."
else
  echo "[validate_ui] Starting gaiaos_ui_tester_mcp on $TESTER_PORT..."
  (cd services/gaiaos_ui_tester_mcp && MCP_PORT="$TESTER_PORT" cargo run > /tmp/gaiaos_mcp.log 2>&1) &
  TESTER_PID=$!
  if ! wait_port 127.0.0.1 "$TESTER_PORT" "tester" 60; then
    echo "[validate_ui] Tester did not become ready. Log:"
    tail -80 /tmp/gaiaos_mcp.log 2>/dev/null || true
    kill "$TESTER_PID" 2>/dev/null || true
    exit 1
  fi
fi

# --- Gateway (8803) ---
if port_listening 127.0.0.1 "$GATEWAY_PORT"; then
  echo "[validate_ui] MCP gateway already on $GATEWAY_PORT, reusing."
else
  if ! command -v uvicorn &>/dev/null; then
    echo "[validate_ui] BLOCKED: port $GATEWAY_PORT not listening and uvicorn not in PATH."
    echo "  Start fot_mcp_gateway on $GATEWAY_PORT with MCP_UI_TESTER_UPSTREAM=$MCP_UI_TESTER_UPSTREAM"
    exit 1
  fi
  echo "[validate_ui] Starting fot_mcp_gateway on $GATEWAY_PORT (upstream $MCP_UI_TESTER_UPSTREAM)..."
  export PYTHONPATH="${REPO_ROOT}/services/fot_mcp_gateway:${REPO_ROOT}/services"
  (cd services/fot_mcp_gateway && MCP_UI_TESTER_UPSTREAM="$MCP_UI_TESTER_UPSTREAM" \
    uvicorn main:app --host 127.0.0.1 --port "$GATEWAY_PORT" > /tmp/gaiaos_gateway.log 2>&1) &
  GW_PID=$!
  if ! wait_port 127.0.0.1 "$GATEWAY_PORT" "gateway" 45; then
    echo "[validate_ui] Gateway did not become ready. Log:"
    tail -80 /tmp/gaiaos_gateway.log 2>/dev/null || true
    kill "$GW_PID" 2>/dev/null || true
    exit 1
  fi
fi

echo "[validate_ui] Running Playwright tests (MCP_BASE_URL=$GATEWAY_URL)..."
cd services/gaiaos_ui_web
MCP_BASE_URL="$GATEWAY_URL" npx playwright test --reporter=list

echo ""
echo "[validate_ui] All tests passed."
