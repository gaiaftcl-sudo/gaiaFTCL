#!/usr/bin/env bash
# Tier A (CI): membrane bin bash syntax + wallet-gate /health on :8803.
# Requires: jq, curl; MCP_BASE_URL defaults to http://127.0.0.1:8803.
# Mac without local compose: set MCP_MESH_HEAD_FALLBACK_URL (default PRIMARY HEAD wallet-gate from mesh map).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

pass=0
fail=0
ok() { echo "PASS $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1"; fail=$((fail + 1)); }

BIN="$ROOT/deploy/mac_cell_mount/bin"
if [[ ! -d "$BIN" ]]; then
  bad "missing $BIN"
  echo "--- PASSED=$pass FAILED=$fail ---"
  exit 1
fi

while IFS= read -r -d '' f; do
  if head -1 "$f" 2>/dev/null | grep -qE '^#!.*(bash|sh)'; then
    bash -n "$f" && ok "bash_n ${f#$BIN/}" || bad "bash_n $f"
  fi
done < <(find "$BIN" -type f ! -name "*.DS_Store" -print0)

MCP_BASE_URL="${MCP_BASE_URL:-http://127.0.0.1:8803}"
MCP_MESH_HEAD_FALLBACK_URL="${MCP_MESH_HEAD_FALLBACK_URL:-http://77.42.85.60:8803}"

out=""
health_base=""
for base in "$MCP_BASE_URL" "$MCP_MESH_HEAD_FALLBACK_URL"; do
  if out=$(curl -sfS -m 12 "${base%/}/health" 2>/dev/null); then
    health_base="$base"
    break
  fi
done

if [[ -z "$out" ]]; then
  bad "MCP gateway /health unreachable at ${MCP_BASE_URL} and fallback ${MCP_MESH_HEAD_FALLBACK_URL}"
  echo "REFUSED: start local wallet-gate, SSH port-forward :8803, or set MCP_MESH_HEAD_FALLBACK_URL."
elif echo "$out" | jq -e '.status == "healthy" or .status == "ok"' >/dev/null 2>&1; then
  ok "gateway_health@${health_base}"
else
  bad "gateway_health_json (unexpected body from ${health_base})"
fi

# /claims needs local wallet-gate + Arango path; mesh-head /claims returns 401-style JSON without wallet headers.
if [[ "${FUSION_PLANT_SKIP_CLAIMS_CURL:-}" == "1" ]]; then
  ok "gateway_claims_skipped_no_arango"
elif [[ "$health_base" != "$MCP_BASE_URL" ]]; then
  ok "gateway_claims_skipped_used_mesh_head_fallback (use localhost tunnel + unset skip for full claims)"
else
  if ! claims=$(curl -sfS "${MCP_BASE_URL}/claims?limit=1" 2>/dev/null); then
    bad "gateway /claims not a JSON array at ${MCP_BASE_URL} (need live Arango or set FUSION_PLANT_SKIP_CLAIMS_CURL=1 for gateway-only slice)"
  else
    echo "$claims" | jq -e 'type == "array"' >/dev/null && ok "gateway_claims_array" || bad "gateway_claims_shape"
  fi
fi

echo "--- PASSED=$pass FAILED=$fail ---"
[[ "$fail" -eq 0 ]]
