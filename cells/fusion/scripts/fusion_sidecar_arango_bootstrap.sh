#!/usr/bin/env sh
# One-shot: ensure gaiaos DB + mcp_claims collection exist (fusion-sidecar compose init).
# POSIX sh (Alpine/BusyBox); safe to re-run (409 ignored).
set -eu
ARANGO_HOST="${ARANGO_HOST:-arangodb}"
PASS="${ARANGO_ROOT_PASSWORD:-gaiaftcl2026}"
BASE="http://${ARANGO_HOST}:8529"

echo "[fusion_sidecar_arango_bootstrap] ${BASE}"

curl -sS -u "root:${PASS}" -X POST "${BASE}/_api/database" \
  -H 'Content-Type: application/json' \
  -d '{"name":"gaiaos"}' || true

curl -sS -u "root:${PASS}" -X POST "${BASE}/_db/gaiaos/_api/collection" \
  -H 'Content-Type: application/json' \
  -d '{"name":"mcp_claims"}' || true

echo "[fusion_sidecar_arango_bootstrap] CALORIE"
