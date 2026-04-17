#!/usr/bin/env bash
# Fusion cell long-run loop — same process, virtual ↔ real via JSON config (re-read each iteration).
# Meaning: run until stop file or SIGINT/SIGTERM — not tied to time of day.
#
# Config: FUSION_CELL_CONFIG (default deploy/fusion_cell/config.json under repo root).
# Stop:   touch LONG_RUN_STOP (default path below) or bash scripts/fusion_cell_long_run_stop.sh
#
# Modes (config long_run.mode + long_run.max_batches, or env):
#   nonstop — run until stop file / signal
#   iterations — exit after max_batches successful batch records (virtual/real), not mooring-only sleeps
# Env: FUSION_LONG_RUN_MODE=nonstop|iterations  FUSION_LONG_RUN_MAX_ITERATIONS=<int> (alias for max_batches)
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CFG="${FUSION_CELL_CONFIG:-$ROOT/deploy/fusion_cell/config.json}"
PROJ="${FUSION_PROJECTION_JSON:-$ROOT/deploy/fusion_mesh/fusion_projection.json}"
STOP_REL="${FUSION_LONG_RUN_STOPFILE:-evidence/fusion_control/LONG_RUN_STOP}"
[[ "$STOP_REL" = /* ]] && STOP_FILE="$STOP_REL" || STOP_FILE="$ROOT/$STOP_REL"

JSONL_REL="${FUSION_LONG_RUN_JSONL:-evidence/fusion_control/long_run_signals.jsonl}"
[[ "$JSONL_REL" = /* ]] && JSONL="$JSONL_REL" || JSONL="$ROOT/$JSONL_REL"

mkdir -p "$(dirname "$STOP_FILE")" "$(dirname "$JSONL")" "$(dirname "$CFG")"

# Deprecated filename: fold into canonical long_run_signals.jsonl (stale DMG / old env may recreate it).
LEGACY_JSONL="$ROOT/evidence/fusion_control/overnight_signals.jsonl"
CANON_JSONL="$ROOT/evidence/fusion_control/long_run_signals.jsonl"
if [[ "$JSONL" == "$CANON_JSONL" && -f "$LEGACY_JSONL" ]]; then
  if [[ ! -f "$JSONL" ]]; then
    mv "$LEGACY_JSONL" "$JSONL"
  else
    cat "$LEGACY_JSONL" >>"$JSONL" && rm -f "$LEGACY_JSONL"
  fi
fi

if [[ ! -f "$CFG" ]]; then
  echo "[fusion_cell_long_run] ERROR: missing config $CFG — copy deploy/fusion_cell/config.example.json"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[fusion_cell_long_run] ERROR: jq required"
  exit 1
fi

LR_MODE="$(jq -r '.long_run.mode // "nonstop"' "$CFG")"
LR_MAX="$(jq -r '.long_run.max_batches // 0' "$CFG")"
[[ -n "${FUSION_LONG_RUN_MODE:-}" ]] && LR_MODE="$FUSION_LONG_RUN_MODE"
if [[ -n "${FUSION_LONG_RUN_MAX_ITERATIONS:-}" ]]; then
  LR_MAX="$FUSION_LONG_RUN_MAX_ITERATIONS"
fi
LR_MODE="$(printf '%s' "$LR_MODE" | tr '[:upper:]' '[:lower:]')"
if [[ "$LR_MODE" != "nonstop" && "$LR_MODE" != "iterations" ]]; then
  echo "[fusion_cell_long_run] WARN: long_run.mode='$LR_MODE' unknown — using nonstop"
  LR_MODE="nonstop"
fi
if ! [[ "$LR_MAX" =~ ^[0-9]+$ ]]; then
  LR_MAX=0
fi
BATCH_DONE=0

if [[ -f "$ROOT/scripts/lib/fusion_mooring.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/scripts/lib/fusion_mooring.sh"
else
  fusion_mooring_mesh_fresh() {
    [[ "${FUSION_MESH_MOORING_REQUIRED:-0}" != "1" ]]
  }
  fusion_mooring_status_json() {
    echo '{"mooring":{"lib_missing":true,"mesh_fresh":false}}'
  }
  fusion_payment_projection_json() {
    [[ -f "$PROJ" ]] && jq -c '.payment_projection // {}' "$PROJ" 2>/dev/null || echo "{}"
  }
fi

projection_s4() {
  # Defaults avoid jq nulls when keys are missing (S4 labels only; not C4 physics).
  if [[ -f "$PROJ" ]]; then
    jq -c '{
      plant_flavor: (.plant_flavor // "generic"),
      dif_profile: (.dif_profile // "default"),
      benchmark_surface_id: (.benchmark_surface_id // "")
    }' "$PROJ" 2>/dev/null || echo '{"plant_flavor":"generic","dif_profile":"default","benchmark_surface_id":""}'
  else
    echo '{"plant_flavor":"generic","dif_profile":"default","benchmark_surface_id":""}'
  fi
}

on_exit() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\n' "{\"control_signal\":\"long_run_halt\",\"ts\":\"$ts\",\"reason\":\"signal_or_exit\",\"runner\":\"fusion_cell\"}" >>"$JSONL"
}
trap on_exit EXIT
trap 'echo "[fusion_cell_long_run] SIGINT"; exit 0' INT
trap 'echo "[fusion_cell_long_run] SIGTERM"; exit 0' TERM

ITER=0
ts0="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n \
  --arg ts "$ts0" \
  --argjson pid "$$" \
  --arg cfg "$CFG" \
  --arg proj "$PROJ" \
  --arg lrm "$LR_MODE" \
  --argjson lrx "$LR_MAX" \
  --argjson s4 "$(projection_s4)" \
  '{control_signal: "long_run_session_start", ts: $ts, pid: $pid, runner: "fusion_cell", config: $cfg, projection_file: $proj, long_run_mode: $lrm, long_run_max_batches: $lrx} + $s4' >>"$JSONL"
echo "[fusion_cell_long_run] pid=$$ config=$CFG mode=$LR_MODE max_batches=$LR_MAX"
echo "[fusion_cell_long_run] stop: touch $STOP_FILE  OR  bash scripts/fusion_cell_long_run_stop.sh"

run_virtual() {
  local bin_rel build_wanted bin
  bin_rel="$(jq -r '.virtual.binary_relative // empty' "$CFG")"
  build_wanted="$(jq -r '.virtual.build_if_missing // true' "$CFG")"

  bin="$ROOT/$bin_rel"
  if [[ ! -x "$bin" ]]; then
    if [[ "$build_wanted" == "true" ]]; then
      echo "[fusion_cell_long_run] building FusionControl (virtual)…"
      export FUSION_SKIP_POST_WITNESS=1
      bash "$ROOT/scripts/build_fusion_control_mac_app.sh" >/dev/null || return 1
    else
      echo "[fusion_cell_long_run] virtual binary missing: $bin"
      return 1
    fi
  fi

  eval "$(jq -r '.virtual.env // {} | to_entries[] | "export \(.key)=\(.value|@sh)"' "$CFG")"
  "$bin"
}

run_real() {
  local len
  len="$(jq '.real.command | length' "$CFG")"
  if [[ "$len" -eq 0 ]]; then
    echo "{\"tokamak_mode\":\"real\",\"blocked\":\"real.command_not_configured\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"c4\":\"REFUSED — set deploy/fusion_cell config.real.command\"}"
    return 2
  fi

  local timeout
  timeout="$(jq -r '.real.timeout_sec // 3600' "$CFG")"
  local -a cmd=()
  while IFS= read -r line; do
    cmd+=("$line")
  done < <(jq -r '.real.command[]' "$CFG")

  eval "$(jq -r '.real.env // {} | to_entries[] | "export \(.key)=\(.value|@sh)"' "$CFG")"

  OUT="$(mktemp)"
  set +e
  if command -v timeout >/dev/null 2>&1; then
    timeout "${timeout}" "${cmd[@]}" >"$OUT" 2>&1
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${timeout}" "${cmd[@]}" >"$OUT" 2>&1
  else
    "${cmd[@]}" >"$OUT" 2>&1
  fi
  local rc=$?
  set -e
  if [[ "$rc" -eq 124 ]]; then
    echo "{\"tokamak_mode\":\"real\",\"error\":\"timeout\",\"timeout_sec\":$timeout}"
    rm -f "$OUT"
    return 1
  fi

  if jq -e . "$OUT" >/dev/null 2>&1; then
    cat "$OUT"
  else
    jq -n --rawfile r "$OUT" --argjson ec "$rc" '{tokamak_mode:"real",exit_code:$ec,stdout:$r}'
  fi
  rm -f "$OUT"
  return "$rc"
}

# Iter 0 ghost (optional): one virtual batch before metered JSONL — not appended (calibration / Franklin hygiene).
_mode_pre="$(jq -r '.tokamak_mode // "virtual"' "$CFG")"
if [[ "${FUSION_LONG_RUN_GHOST_PRIME:-0}" == "1" ]] && [[ "$_mode_pre" == "virtual" ]]; then
  echo "[fusion_cell_long_run] FUSION_LONG_RUN_GHOST_PRIME=1 — silent virtual prime (no JSONL line)"
  run_virtual >/dev/null 2>&1 || true
fi

while true; do
  if [[ -f "$STOP_FILE" ]]; then
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\n' "{\"control_signal\":\"long_run_stop_file\",\"ts\":\"$ts\",\"iter\":$ITER}" >>"$JSONL"
    rm -f "$STOP_FILE"
    echo "[fusion_cell_long_run] stop file — exit"
    trap - EXIT
    exit 0
  fi

  ITER=$((ITER + 1))
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  mstat="$(fusion_mooring_status_json)"
  ppay="$(fusion_payment_projection_json)"

  if [[ "${FUSION_MESH_MOORING_REQUIRED:-0}" == "1" ]] && ! fusion_mooring_mesh_fresh; then
    jq -n \
      --argjson iter "$ITER" \
      --arg ts "$ts" \
      --argjson s4 "$(projection_s4)" \
      --argjson mstat "$mstat" \
      --argjson payproj "$ppay" \
      '{control_signal: "fusion_mooring_degraded", reason: "mesh_heartbeat_stale_or_missing", iter: $iter, ts: $ts} + $s4 + $mstat + {payment_projection: $payproj}' >>"$JSONL"
    echo "[fusion_cell_long_run] mooring: mesh heartbeat stale — DEGRADED OFF (set NATS + run fusion_mesh_mooring_heartbeat.sh)"
    sleep 60
    continue
  fi

  CELL_ID_ENV="${CELL_ID:-}"
  mode="$(jq -r '.tokamak_mode // "virtual"' "$CFG")"
  cell_id="$(jq -r '.cell_id // "cell"' "$CFG")"
  if [[ -n "$CELL_ID_ENV" ]]; then
    cell_id="$CELL_ID_ENV"
  fi

  OUT="$(mktemp)"
  set +e
  case "$mode" in
    virtual)
      run_virtual >"$OUT" 2>/dev/null
      rc=$?
      ;;
    real)
      run_real >"$OUT" 2>/dev/null
      rc=$?
      ;;
    *)
      echo "{\"error\":\"unknown tokamak_mode\",\"mode\":\"$mode\"}" >"$OUT"
      rc=1
      ;;
  esac
  set -e

  if jq -e . "$OUT" >/dev/null 2>&1; then
    jq -c --argjson iter "$ITER" --argjson ec "$rc" --arg ts "$ts" --arg mode "$mode" --arg cid "$cell_id" --argjson s4 "$(projection_s4)" --argjson mstat "$mstat" --argjson payproj "$ppay" \
      '. + {control_signal: "fusion_cell_batch", iter: $iter, ts: $ts, exit_code: $ec, tokamak_mode: $mode, cell_id: $cid} + $s4 + $mstat + {payment_projection: $payproj}' "$OUT" >>"$JSONL"
  else
    jq -n \
      --argjson iter "$ITER" \
      --arg ts "$ts" \
      --argjson ec "$rc" \
      --arg mode "$mode" \
      --arg cid "$cell_id" \
      --argjson s4 "$(projection_s4)" \
      --argjson mstat "$mstat" \
      --argjson payproj "$ppay" \
      --argjson raw "$(jq -Rs . <"$OUT")" \
      '{control_signal: "fusion_cell_batch", iter: $iter, ts: $ts, exit_code: $ec, tokamak_mode: $mode, cell_id: $cid, raw: $raw} + $s4 + $mstat + {payment_projection: $payproj}' >>"$JSONL"
  fi
  rm -f "$OUT"

  if [[ "$rc" -ne 0 ]] && [[ "$rc" -ne 2 ]]; then
    echo "[fusion_cell_long_run] iter=$ITER mode=$mode rc=$rc (continuing)"
  fi
  if [[ "$rc" -eq 2 ]]; then
    echo "[fusion_cell_long_run] iter=$ITER real mode BLOCKED (no command) — sleep 60s"
    sleep 60
  fi

  BATCH_DONE=$((BATCH_DONE + 1))
  if [[ "$LR_MODE" == "iterations" ]] && [[ "$LR_MAX" -gt 0 ]] && [[ "$BATCH_DONE" -ge "$LR_MAX" ]]; then
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\n' "{\"control_signal\":\"long_run_iterations_complete\",\"ts\":\"$ts\",\"batches_completed\":$BATCH_DONE,\"max_batches\":$LR_MAX}" >>"$JSONL"
    echo "[fusion_cell_long_run] completed max_batches=$LR_MAX — exit"
    trap - EXIT
    exit 0
  fi
done
