#!/usr/bin/env bash
# fot_mcp_gateway (substrate map: port 8803). MCP_BASE_URL may include another host if tunneled.
set -euo pipefail
MCP_BASE_URL="${MCP_BASE_URL:-http://127.0.0.1:8803}"
if curl -sfS -m 5 "${MCP_BASE_URL}/health" | jq -e '.status == "healthy" or .status == "ok"' >/dev/null 2>&1; then
  echo "OK gateway ${MCP_BASE_URL}/health"
  exit 0
fi
MCP_MESH_HEAD_FALLBACK_URL="${MCP_MESH_HEAD_FALLBACK_URL:-http://77.42.85.60:8803}"
if [[ "$MCP_BASE_URL" != "$MCP_MESH_HEAD_FALLBACK_URL" ]] && curl -sfS -m 12 "${MCP_MESH_HEAD_FALLBACK_URL}/health" | jq -e '.status == "healthy" or .status == "ok"' >/dev/null 2>&1; then
  echo "OK gateway fallback ${MCP_MESH_HEAD_FALLBACK_URL}/health (local ${MCP_BASE_URL} unreachable)"
  exit 0
fi
echo "REFUSED: gateway not healthy/ok at ${MCP_BASE_URL} (tried fallback ${MCP_MESH_HEAD_FALLBACK_URL})"
exit 1
