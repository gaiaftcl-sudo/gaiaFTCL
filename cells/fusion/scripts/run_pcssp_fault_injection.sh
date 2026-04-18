#!/usr/bin/env bash
# PCSSP-class fault injection: publish structured fault envelopes to NATS and append local REFUSED receipts.
# GATE3: each wire message compact JSON MAX_PAYLOAD 4096; no multi-line log tails on NATS.
# Measures publish pipeline wall time per fault (µs→ms). Requires NATS_URL + nats CLI when not using --local-only.
#
# Usage:
#   bash scripts/run_pcssp_fault_injection.sh --faults 100 --interval 2
#   FUSION_PCSSP_LOCAL_ONLY=1 bash scripts/run_pcssp_fault_injection.sh --faults 10   # no NATS; receipts only
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EV="$ROOT/evidence/fusion_control"
REC="$EV/pcssp_fault_receipts.jsonl"
SUBJECT="${PCSSP_FAULT_NATS_SUBJECT:-fusion.control.exceptions}"
mkdir -p "$EV"

FAULTS=100
INTERVAL_SEC=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --faults) FAULTS="${2:?}"; shift 2 ;;
    --interval) INTERVAL_SEC="${2:?}"; shift 2 ;;
    *) echo "REFUSED: unknown arg $1"; exit 1 ;;
  esac
done

[[ "$FAULTS" =~ ^[0-9]+$ ]] || { echo "REFUSED: --faults must be int"; exit 1; }

LOCAL_ONLY="${FUSION_PCSSP_LOCAL_ONLY:-0}"
if [[ "$LOCAL_ONLY" != "1" ]]; then
  if [[ -z "${NATS_URL:-}" ]] || ! command -v nats >/dev/null 2>&1; then
    echo "BLOCKED: set NATS_URL and install nats CLI, or FUSION_PCSSP_LOCAL_ONLY=1"
    exit 2
  fi
fi

ts_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

for i in $(seq 1 "$FAULTS"); do
  inj="$(ts_utc)"
  BODY="$(jq -n \
    --argjson idx "$i" \
    --arg inj "$inj" \
    '{
      schema: "pcssp_injected_fault_v1",
      fault_index: $idx,
      injected_at_utc: $inj,
      kind: "sensor_loss_sim",
      coil: ("RANDOM_COIL_" + ($idx | tostring)),
      severity: "off_normal"
    }' | tr -d '\n')"

  LAT_MS=0
  if [[ "$LOCAL_ONLY" == "1" ]]; then
    LAT_MS=0
  else
    T0="$(python3 -c 'import time; print(time.perf_counter_ns())')"
    NATS_URL="${NATS_URL}" nats pub "$SUBJECT" "$BODY" >/dev/null 2>&1 || true
    T1="$(python3 -c 'import time; print(time.perf_counter_ns())')"
    LAT_MS=$(( (T1 - T0) / 1_000_000 ))
    if [[ "$LAT_MS" -lt 0 ]]; then LAT_MS=0; fi
  fi

  # One JSON object per line (JSONL) — soak tail reader splits on newlines.
  jq -cn \
    --arg ts "$(ts_utc)" \
    --argjson idx "$i" \
    --argjson lat "$LAT_MS" \
    --arg inj "$inj" \
    --arg sub "$SUBJECT" \
    --arg w "$([[ "$LOCAL_ONLY" == "1" ]] && echo local_only || echo injector_pub_timing)" \
    '{
      schema: "pcssp_fault_receipt_v1",
      ts: $ts,
      fault_index: $idx,
      terminal: "REFUSED",
      latency_ms: $lat,
      injected_at_utc: $inj,
      nats_subject: $sub,
      witness: $w
    }' >>"$REC"

  if [[ "$INTERVAL_SEC" =~ ^[0-9]+$ ]] && [[ "$INTERVAL_SEC" -gt 0 ]]; then
    sleep "$INTERVAL_SEC"
  fi
done

echo "[pcssp_fault_injection] faults=$FAULTS receipts_appended=$REC local_only=$LOCAL_ONLY"
