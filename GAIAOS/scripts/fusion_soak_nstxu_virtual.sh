#!/usr/bin/env bash
# NSTX-U / Metal sovereign soak: repeated fusion_control batches with ε/τ gates vs industry ceilings.
# Writes violations to evidence/fusion_control/soak_violations.jsonl (does not replace long_run_signals.jsonl).
#
# τ metric (important):
#   FUSION_SOAK_TAU_METRIC=gpu_ms  — DEFAULT. Gates on receipt gpu_wall_us vs budgets (µs). Matches fusion_control:
#     hot Metal dispatch after optional warmup — this is what prebuilt metallib + ghost prime optimizes.
#   FUSION_SOAK_TAU_METRIC=wall_ms — End-to-end batch time (warmup + GPU + CPU verify). Use for host stress /
#     “other apps eating the Mac” experiments, not for claiming the kernel failed the 3 ms story.
#
# Concurrency: one soak instance per machine by default (PID lock). Override with FUSION_SOAK_FORCE_PARALLEL=1
# if you intentionally run overlapping soaks as a stress test.
#
# Env:
#   FUSION_SOAK_TARGET_BATCHES   — default 10
#   FUSION_SOAK_MAX_WALL_SEC     — optional wall-clock cap (0 = unlimited)
#   FUSION_VALIDATION_CYCLES     — cycles per batch (default 500); use FUSION_ALLOW_HIGH_CYCLES=1 for up to 1e6 in one batch
#   FUSION_SOAK_STOP_FILE        — touch to stop gracefully (default evidence/fusion_control/SOAK_STOP)
#   FUSION_SOAK_EMAX_CEIL        — default 9.54e-7 (jq numeric compare)
#   FUSION_SOAK_TAU_INDUSTRY_MS  — default 5
#   FUSION_SOAK_TAU_TARGET_MS   — default 3
#   FUSION_SOAK_TAU_METRIC       — gpu_ms | wall_ms (default gpu_ms)
#   FUSION_SOAK_FORCE_PARALLEL   — set to 1 to skip single-instance lock
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
EV="$ROOT/evidence/fusion_control"
mkdir -p "$EV"
VIOL="$EV/soak_violations.jsonl"
SOAK_LOCK="${FUSION_SOAK_LOCK:-$EV/fusion_soak.pid}"

if [[ "${FUSION_SOAK_FORCE_PARALLEL:-0}" != "1" ]]; then
  if [[ -f "$SOAK_LOCK" ]]; then
    oldpid="$(tr -d ' \n' <"$SOAK_LOCK" 2>/dev/null || true)"
    if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null; then
      echo "[fusion_soak] REFUSED: another soak is already running (pid $oldpid). Stop it or export FUSION_SOAK_FORCE_PARALLEL=1 for intentional overlap stress."
      exit 1
    fi
  fi
  echo $$ >"$SOAK_LOCK"
  trap 'rm -f "$SOAK_LOCK"' EXIT
fi

CFG="${FUSION_CELL_CONFIG:-$ROOT/deploy/fusion_cell/config.json}"
BIN_REL="$(jq -r '.virtual.binary_relative // "services/fusion_control_mac/dist/FusionControl.app/Contents/MacOS/fusion_control"' "$CFG")"
APP="$ROOT/$BIN_REL"

TARGET="${FUSION_SOAK_TARGET_BATCHES:-10}"
MAXWALL="${FUSION_SOAK_MAX_WALL_SEC:-0}"
STOPF="${FUSION_SOAK_STOP_FILE:-$EV/SOAK_STOP}"
E_CEIL="${FUSION_SOAK_EMAX_CEIL:-9.54e-7}"
TAU_IND="${FUSION_SOAK_TAU_INDUSTRY_MS:-5}"
TAU_TGT="${FUSION_SOAK_TAU_TARGET_MS:-3}"
TAU_METRIC="$(printf '%s' "${FUSION_SOAK_TAU_METRIC:-gpu_ms}" | tr '[:upper:]' '[:lower:]')"
if [[ "$TAU_METRIC" != "gpu_ms" && "$TAU_METRIC" != "wall_ms" ]]; then
  echo "[fusion_soak] WARN: unknown FUSION_SOAK_TAU_METRIC=$TAU_METRIC — using gpu_ms"
  TAU_METRIC="gpu_ms"
fi
IND_US=$((TAU_IND * 1000))
TGT_US=$((TAU_TGT * 1000))

export FUSION_VALIDATION_CYCLES="${FUSION_VALIDATION_CYCLES:-500}"

if [[ ! -x "$APP" ]]; then
  echo "[fusion_soak] building FusionControl…"
  export FUSION_SKIP_POST_WITNESS=1
  bash "$ROOT/scripts/build_fusion_control_mac_app.sh" >/dev/null
fi

command -v jq >/dev/null || { echo "REFUSED: jq required"; exit 1; }

ts_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

START_TS="$(ts_utc)"
START_EPOCH=$(date +%s)
echo "[fusion_soak] start=$START_TS batches=$TARGET cycles_per_batch=$FUSION_VALIDATION_CYCLES emax_ceil=$E_CEIL tau_industry_ms=$TAU_IND tau_target_ms=$TAU_TGT tau_metric=$TAU_METRIC"
if [[ "$TAU_METRIC" == "gpu_ms" ]]; then
  echo "[fusion_soak] tau_note: gates compare gpu_wall_us to budgets (≤${IND_US}µs industry, ≤${TGT_US}µs target). For full-batch host stress use FUSION_SOAK_TAU_METRIC=wall_ms."
else
  echo "[fusion_soak] tau_note: gates compare wall_time_ms (end-to-end: warmup + GPU + verify). Expect higher τ under load — good for Mac-cell contention experiments."
fi
echo "[fusion_soak] cycle_cap_note: FUSION_ALLOW_HIGH_CYCLES=1 allows up to 1000000 inner cycles per batch (see fusion_control_mac parse_cycles)"

ok_batches=0
fail_batches=0
batch_idx=0

while true; do
  if [[ -f "$STOPF" ]]; then
    echo "[fusion_soak] stop file present — exiting"
    rm -f "$STOPF"
    break
  fi
  if [[ "$batch_idx" -ge "$TARGET" ]]; then
    break
  fi
  if [[ "$MAXWALL" =~ ^[0-9]+$ ]] && [[ "$MAXWALL" -gt 0 ]]; then
    now=$(date +%s)
    if [[ $((now - START_EPOCH)) -ge "$MAXWALL" ]]; then
      echo "[fusion_soak] max wall seconds reached ($MAXWALL)"
      break
    fi
  fi

  batch_idx=$((batch_idx + 1))
  OUT="$(mktemp)"
  set +e
  "$APP" >"$OUT" 2>/dev/null
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]] || ! jq -e . "$OUT" >/dev/null 2>&1; then
    fail_batches=$((fail_batches + 1))
    jq -n \
      --arg ts "$(ts_utc)" \
      --argjson bi "$batch_idx" \
      --argjson rc "$rc" \
      '{schema: "fusion_soak_violation_v1", ts: $ts, batch_index: $bi, reason: "fusion_control_failed_or_nonjson", exit_code: $rc}' >>"$VIOL"
    rm -f "$OUT"
    continue
  fi

  okv="$(jq -r '.ok' "$OUT")"
  worst="$(jq -r '.worst_max_abs_error // 0' "$OUT")"
  wms="$(jq -r '.wall_time_ms // empty' "$OUT")"
  gpus="$(jq -r '.gpu_wall_us // empty' "$OUT")"
  cyc="$(jq -r '.cycles_completed // 0' "$OUT")"

  viol=0
  reasons=()
  if [[ "$okv" != "true" ]]; then
    viol=1
    reasons+=("ok_false")
  fi
  if awk -v w="$worst" -v c="$E_CEIL" 'BEGIN{exit (w+0 < c+0 ? 0 : 1)}'; then
    :
  else
    viol=1
    reasons+=("emax_above_ceil")
  fi

  if [[ "$TAU_METRIC" == "gpu_ms" ]]; then
    if [[ "$gpus" =~ ^[0-9]+$ ]]; then
      if [[ "$gpus" -gt "$IND_US" ]]; then
        viol=1
        reasons+=("tau_gpu_above_industry_us")
      fi
      if [[ "$gpus" -gt "$TGT_US" ]]; then
        viol=1
        reasons+=("tau_gpu_above_target_us")
      fi
    else
      viol=1
      reasons+=("tau_gpu_missing")
    fi
  else
    if [[ "$wms" =~ ^[0-9]+$ ]]; then
      if [[ "$wms" -gt "$TAU_IND" ]]; then
        viol=1
        reasons+=("tau_wall_above_industry_ms")
      fi
      if [[ "$wms" -gt "$TAU_TGT" ]]; then
        viol=1
        reasons+=("tau_wall_above_target_ms")
      fi
    else
      viol=1
      reasons+=("tau_wall_missing")
    fi
  fi

  if [[ "$viol" -eq 1 ]]; then
    fail_batches=$((fail_batches + 1))
    jq -n \
      --arg ts "$(ts_utc)" \
      --arg tm "$TAU_METRIC" \
      --argjson bi "$batch_idx" \
      --arg worst "$worst" \
      --argjson wms "$wms" \
      --argjson gpus "$gpus" \
      --argjson cyc "$cyc" \
      --argjson reasons "$(printf '%s\n' "${reasons[@]}" | jq -R . | jq -s .)" \
      '{schema: "fusion_soak_violation_v1", ts: $ts, batch_index: $bi, tau_metric: $tm, worst_max_abs_error: ($worst|tonumber), wall_time_ms: $wms, gpu_wall_us: $gpus, cycles_completed: $cyc, reasons: $reasons}' >>"$VIOL"
  else
    ok_batches=$((ok_batches + 1))
  fi
  rm -f "$OUT"
done

END_TS="$(ts_utc)"
echo "[fusion_soak] end=$END_TS ok_batches=$ok_batches fail_batches=$fail_batches batches_attempted=$batch_idx"
echo "[fusion_soak] violations_log=$VIOL"
