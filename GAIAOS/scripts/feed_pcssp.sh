#!/usr/bin/env bash
# One-shot (or loop) publisher for ITER PCSSP-class **surface descriptor** witness — not a full pulse archive.
# Publishes the M8 JSON envelope to fusion.control.exceptions when NATS_URL + nats CLI exist.
# GATE3: single compact JSON per pub MAX_PAYLOAD 4096; not raw jsonl stream on NATS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUBJECT="${PCSSP_NATS_SUBJECT:-fusion.control.exceptions}"
PAYLOAD="$ROOT/deploy/fusion_mesh/config/benchmarks/iter_pcssp_v1.json"

[[ -f "$PAYLOAD" ]] || { echo "REFUSED: missing $PAYLOAD"; exit 1; }
LAST="$ROOT/evidence/fusion_control/feed_pcssp_last.json"
mkdir -p "$(dirname "$LAST")"
BODY="$(jq -c '
  . as $p
  | ($p + {
      published_at_utc: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
      s4_witness_sat: {
        alarm_id: "pcssp_surface_descriptor_v1",
        interlock_state_vector: "S4_SURFACE_ONLY_NOT_PLC",
        operator_ack_or_auto_safe_state: "AUTO_SAFE_SURFACE_PUBLISH"
      }
    })
  | del(.franklin_alignment, .external_ingest_note, .stack, .canonical_uri)
' "$PAYLOAD")"

if [[ -n "${NATS_URL:-}" ]] && command -v nats >/dev/null 2>&1; then
  NATS_URL="${NATS_URL}" nats pub "$SUBJECT" "$BODY"
  echo "$BODY" | jq '.' >"$LAST.tmp"
  mv "$LAST.tmp" "$LAST"
  echo "CALORIE: published PCSSP surface witness to $SUBJECT; receipt=$LAST"
else
  echo "BLOCKED: set NATS_URL and install nats CLI for wire hit; payload:" >&2
  echo "$BODY" >&2
  exit 2
fi
