#!/usr/bin/env bash
# NSTX-U / OSTI-2510881–style benchmark → NATS + S⁴ shadow file (umbilical for PCS display).
# GATE3: one compact line per wire message MAX_PAYLOAD 4096; source data file stays on disk — not whole-file wire dump.
# Does NOT run on UI Refresh; start beside Next.js. Not Franklin — plain bash + jq (+ optional nats CLI).
#
#   NATS_URL=nats://127.0.0.1:4222 bash scripts/nstxu_benchmark_feeder.sh \
#     --file deploy/fusion_mesh/config/benchmarks/osti_2510881_plasma_shot.sample.jsonl \
#     --fps 2 \
#     --subject gaiaftcl.fusion.benchmark.pcs.v1
#
# Writes: evidence/fusion_control/benchmark_pcs_shadow.json (GET /api/fusion/s4-projection reads it).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FILE="$ROOT/deploy/fusion_mesh/config/benchmarks/osti_2510881_plasma_shot.sample.jsonl"
FPS="2"
SUBJECT="${NATS_SUBJECT:-gaiaftcl.fusion.benchmark.pcs.v1}"
SHADOW="$ROOT/evidence/fusion_control/benchmark_pcs_shadow.json"
mkdir -p "$(dirname "$SHADOW")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="${2:?}"; shift 2 ;;
    --fps) FPS="${2:?}"; shift 2 ;;
    --subject) SUBJECT="${2:?}"; shift 2 ;;
    *) echo "REFUSED: unknown arg $1"; exit 1 ;;
  esac
done

[[ -f "$FILE" ]] || { echo "REFUSED: missing --file $FILE"; exit 1; }
command -v jq >/dev/null || { echo "REFUSED: jq required"; exit 1; }

delay="$(jq -n --argjson f "$FPS" 'if ($f | tonumber) > 0 then 1 / ($f | tonumber) else 0.5 end')"
echo "[nstxu_benchmark_feeder] file=$FILE fps=$FPS subject=$SUBJECT shadow=$SHADOW"

cycle() {
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[$'\t\r\n ']/}" ]] && continue
    echo "$line" | jq -e '.te_kev and .ti_kev' >/dev/null 2>&1 || continue
    echo "$line" | jq --arg schema gaiaftcl_benchmark_pcs_shadow_v1 '
      {
        schema: $schema,
        emulation_active: true,
        te_kev: .te_kev,
        ti_kev: .ti_kev,
        ts_utc: (.ts // (now | strftime("%Y-%m-%dT%H:%M:%SZ"))),
        source_tag: "osti_2510881_emulated",
        note: "S4 shadow for UI; not fusion_live_hardware attestation.",
        s4_witness_sat: {
          shot_or_scenario_id: (.shot_id // "unknown_shot"),
          pcs_session_id: "benchmark_feeder_session",
          simulink_log_digest: "S4_SHADOW_ONLY_NOT_TOKSYS_SIMULINK"
        }
      }
    ' >"$SHADOW.tmp"
    mv "$SHADOW.tmp" "$SHADOW"
    if command -v nats >/dev/null 2>&1 && [[ -n "${NATS_URL:-}" ]]; then
      NATS_URL="${NATS_URL}" nats pub "$SUBJECT" "$line" 2>/dev/null || true
    fi
    sleep "$delay"
  done <"$FILE"
}

while true; do
  cycle
  sleep 1
done
