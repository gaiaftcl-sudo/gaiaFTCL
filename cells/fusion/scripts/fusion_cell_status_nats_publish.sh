#!/usr/bin/env bash
# Publish compact Fusion cell status to NATS (gaiaftcl.fusion.cell.status.v1). MAX_PAYLOAD 4096; no JSONL on wire.
# Prereqs: jq, nats CLI **or** Docker (natsio/nats-box) for publish. Env: NATS_URL, GAIA_ROOT.
# Mac without `nats` on PATH: set NATS_URL=nats://host.docker.internal:4222 and ensure Docker is running.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
SUBJECT="${FUSION_CELL_STATUS_NATS_SUBJECT:-gaiaftcl.fusion.cell.status.v1}"
NATS_URL="${NATS_URL:-nats://127.0.0.1:4222}"
JSONL="${FUSION_LONG_RUN_JSONL:-$GAIA_ROOT/evidence/fusion_control/long_run_signals.jsonl}"
PID_FILE="$GAIA_ROOT/evidence/fusion_control/fusion_cell_long_run.pid"

die() { echo "REFUSED: fusion_cell_status_nats_publish: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq required"

nats_pub() {
  local sub="$1"
  local msg="$2"
  # Prefer nats-py when available (nats CLI / nats-box often disagree with host networking vs local server).
  if python3 -c "import nats" 2>/dev/null; then
    NATS_URL="$NATS_URL" NATS_PUB_SUBJECT="$sub" NATS_PUB_BODY="$msg" python3 - <<'PY'
import asyncio
import os
import nats

async def main() -> None:
    nc = await nats.connect(os.environ["NATS_URL"], connect_timeout=15)
    await nc.publish(os.environ["NATS_PUB_SUBJECT"], os.environ["NATS_PUB_BODY"].encode("utf-8"))
    await nc.drain()

asyncio.run(main())
PY
    return
  fi
  if command -v nats >/dev/null 2>&1; then
    export NATS_URL
    nats pub "$sub" "$msg"
    return
  fi
  command -v docker >/dev/null 2>&1 || die "nats-py, nats CLI, and docker not available for publish"
  docker run --rm -e NATS_URL="$NATS_URL" natsio/nats-box:latest nats pub "$sub" "$msg"
}

IDENT="${HOME}/.gaiaftcl/cell_identity.json"
[[ -f "$IDENT" ]] || die "missing $IDENT"

cell_id="$(jq -r '.cell_id // empty' "$IDENT")"
[[ -n "$cell_id" ]] || die "cell_identity.json missing cell_id"

mesh_ok_json="false"
if bash "$GAIA_ROOT/scripts/fusion_moor_preflight.sh" >/dev/null 2>&1; then
  mesh_ok_json="true"
fi

lr_run_json="false"
if [[ -f "$PID_FILE" ]]; then
  pid="$(tr -d ' \n' <"$PID_FILE" || true)"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    lr_run_json="true"
  fi
fi

last_line=""
if [[ -f "$JSONL" ]]; then
  last_line="$(tail -n 1 "$JSONL" 2>/dev/null || true)"
fi

signals_tail_hash="none"
if [[ -n "$last_line" ]]; then
  signals_tail_hash="$(printf '%s' "$last_line" | shasum -a 256 2>/dev/null | awk '{print $1}')"
fi

last_wall_ms="null"
last_gpu_us="null"
last_worst_emax="null"
if [[ -n "$last_line" ]]; then
  last_wall_ms="$(printf '%s' "$last_line" | jq -c '.wall_ms // .last_wall_ms // null' 2>/dev/null || echo null)"
  last_gpu_us="$(printf '%s' "$last_line" | jq -c '.gpu_us // .last_gpu_us // null' 2>/dev/null || echo null)"
  last_worst_emax="$(printf '%s' "$last_line" | jq -c '.worst_emax // .last_worst_emax // null' 2>/dev/null || echo null)"
fi

git_sha="$(git -C "$GAIA_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

meta_lib=""
ml="$GAIA_ROOT/evidence/fusion_control/metal_fusion.metallib"
if [[ -f "$ml" ]]; then
  meta_lib="$(shasum -a 256 "$ml" 2>/dev/null | awk '{print substr($1,1,12)}')"
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

body="$(jq -n \
  --arg schema "gaiaftcl_fusion_cell_status_v1" \
  --arg cell_id "$cell_id" \
  --arg ts_utc "$ts" \
  --argjson mesh_moor_ok "$mesh_ok_json" \
  --argjson long_run_running "$lr_run_json" \
  --argjson last_wall_ms "${last_wall_ms:-null}" \
  --argjson last_gpu_us "${last_gpu_us:-null}" \
  --argjson last_worst_emax "${last_worst_emax:-null}" \
  --arg git_sha "$git_sha" \
  --arg signals_tail_hash "$signals_tail_hash" \
  --arg metallib_hash_short "${meta_lib:-}" \
  '{
    schema: $schema,
    cell_id: $cell_id,
    ts_utc: $ts_utc,
    mesh_moor_ok: $mesh_moor_ok,
    long_run_running: $long_run_running,
    last_wall_ms: $last_wall_ms,
    last_gpu_us: $last_gpu_us,
    last_worst_emax: $last_worst_emax,
    soak_pass_counts: {},
    git_sha: $git_sha,
    metallib_hash_short: (if ($metallib_hash_short|length) > 0 then $metallib_hash_short else null end),
    signals_tail_hash: $signals_tail_hash
  }')"

bytes="$(printf '%s' "$body" | wc -c | tr -d ' ')"
[[ "$bytes" -le 4096 ]] || die "payload $bytes bytes > 4096"

nats_pub "$SUBJECT" "$body"
echo "CALORIE: published $SUBJECT (${bytes} bytes) cell_id=$cell_id"
