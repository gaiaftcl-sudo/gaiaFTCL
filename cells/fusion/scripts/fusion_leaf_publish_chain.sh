#!/usr/bin/env bash
# One-shot: mesh mooring heartbeat + fusion cell status publish (Mac leaf; Docker NATS fallback inside scripts).
# Env: NATS_URL (default nats://host.docker.internal:4222 on Mac Docker Desktop), GAIA_ROOT.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
export NATS_URL="${NATS_URL:-nats://host.docker.internal:4222}"

bash "$ROOT/deploy/mac_cell_mount/bin/fusion_mesh_mooring_heartbeat.sh"
bash "$ROOT/scripts/fusion_cell_status_nats_publish.sh"
echo "CALORIE: fusion_leaf_publish_chain OK (NATS_URL=$NATS_URL)"
