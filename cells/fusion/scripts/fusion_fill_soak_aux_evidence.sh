#!/usr/bin/env bash
# Append PCSSP REFUSED receipts (local) + TORAX episode lines derived from Metal JSONL tail.
# Requires: jq, python3. Run from repo root or any cwd (script resolves GAIA_ROOT).
#
# Usage:
#   bash scripts/fusion_fill_soak_aux_evidence.sh
#   PCSSP_FAULTS=24 bash scripts/fusion_fill_soak_aux_evidence.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GAIA_ROOT="${GAIA_ROOT:-$ROOT}"
EV="$GAIA_ROOT/evidence/fusion_control"
mkdir -p "$EV"

PCSSP_FAULTS="${PCSSP_FAULTS:-16}"
PCSSP_JSONL="$EV/pcssp_fault_receipts.jsonl"

command -v jq >/dev/null 2>&1 || { echo "REFUSED: jq required for PCSSP injector"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "REFUSED: python3 required"; exit 2; }

echo "[fusion_fill_soak_aux] GAIA_ROOT=$GAIA_ROOT PCSSP_FAULTS=$PCSSP_FAULTS"

# Older injector wrote pretty-printed blocks; soak tail expects one JSON per line.
if [[ -f "$PCSSP_JSONL" ]]; then
  l2="$(sed -n '2p' "$PCSSP_JSONL" 2>/dev/null || true)"
  if [[ "$l2" =~ ^[[:space:]]+\"schema\" ]]; then
    : >"$PCSSP_JSONL"
    echo "[fusion_fill_soak_aux] cleared legacy multi-line PCSSP file (re-run uses JSONL)"
  fi
fi

FUSION_PCSSP_LOCAL_ONLY=1 bash "$ROOT/scripts/run_pcssp_fault_injection.sh" --faults "$PCSSP_FAULTS"

TORAX_FEEDER_READY=1 TORAX_RUN_CMD="python3 ${ROOT}/scripts/torax_emit_from_jsonl_tail.py" \
  python3 "$ROOT/scripts/feed_torax.py"

echo "[fusion_fill_soak_aux] done — refresh /fusion-s4 soak table"
