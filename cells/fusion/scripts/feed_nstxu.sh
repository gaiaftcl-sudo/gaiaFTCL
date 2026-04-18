#!/usr/bin/env bash
# Industry-facing wrapper → NSTX-U / OSTI-style JSONL loop + NATS + benchmark_pcs_shadow.json.
# Default NATS subject: fusion.telemetry.magnetics (mesh leaf naming; adjust with --subject).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export NATS_SUBJECT="${NATS_SUBJECT:-fusion.telemetry.magnetics}"
exec bash "$ROOT/scripts/nstxu_benchmark_feeder.sh" \
  --file "${NSTXU_FEED_FILE:-$ROOT/deploy/fusion_mesh/config/benchmarks/osti_2510881_plasma_shot.sample.jsonl}" \
  --fps "${NSTXU_FEED_FPS:-2}" \
  --subject "$NATS_SUBJECT"
