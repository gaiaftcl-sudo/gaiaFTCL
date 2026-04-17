#!/usr/bin/env bash
# Full gaiaos_ui_web `test:fusion:all` with MCP on localhost:8803 (fusion-sidecar compose).
# /claims needs Arango; this sets FUSION_PLANT_SKIP_CLAIMS_CURL=1 for the gateway-only slice.
# For strict /claims: point MCP_BASE_URL at mesh head (tunnel) and run npm run test:fusion:all without this script.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"

cleanup() {
  docker compose -f "$ROOT/docker-compose.fusion-sidecar.yml" down >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker compose -f "$ROOT/docker-compose.fusion-sidecar.yml" up -d
sleep 4
(
  cd "$ROOT/services/gaiaos_ui_web"
  export FUSION_PLANT_SKIP_CLAIMS_CURL=1
  npm run test:fusion:all
)
