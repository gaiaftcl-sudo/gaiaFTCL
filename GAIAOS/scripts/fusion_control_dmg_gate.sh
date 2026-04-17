#!/usr/bin/env bash
# DMG release gate: build FusionControl.app + run 2000 Metal cycles + write JSON evidence.
# Entropy tax line: €0.10/kW × FUSION_DECLARED_KW (default 1.0 kW for gate = €0.10 due declarative).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVD="$ROOT/evidence/fusion_control"
mkdir -p "$EVD"

export FUSION_SKIP_POST_WITNESS=1
bash "$ROOT/scripts/build_fusion_control_mac_app.sh"

APP="$ROOT/services/fusion_control_mac/dist/FusionControl.app/Contents/MacOS/fusion_control"
OUT="$EVD/dmg_gate_2000_cycle_receipt.json"

export FUSION_VALIDATION_CYCLES="${FUSION_VALIDATION_CYCLES:-2000}"
export FUSION_DECLARED_KW="${FUSION_DECLARED_KW:-1.0}"
export FUSION_ENTROPY_TAX_EUR_PER_KW="${FUSION_ENTROPY_TAX_EUR_PER_KW:-0.10}"

echo "[fusion_control_dmg_gate] running ${FUSION_VALIDATION_CYCLES} cycles, declared_kw=${FUSION_DECLARED_KW}, rate=${FUSION_ENTROPY_TAX_EUR_PER_KW} EUR/kW"
"$APP" | tee "$OUT"

if ! command -v jq >/dev/null 2>&1; then
  echo "[fusion_control_dmg_gate] ERROR: jq required to verify receipt"
  exit 1
fi

jq -e '.ok == true and .cycles_completed == .cycles_requested and .schema == "fusion_control_batch_receipt_v1"' "$OUT" >/dev/null

echo "[fusion_control_dmg_gate] PASS — evidence: $OUT"
