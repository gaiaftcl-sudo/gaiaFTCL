#!/usr/bin/env bash
# Publish register_team JSON to NATS (consumers: fusion_challenge_nats_consumer.py → HTTP ledger, or manual CLI).
# GATE3: compact envelope MAX_PAYLOAD 4096; not gaiaftcl.fusion.cell.status.v1 (challenge ledger subject).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM="${1:?usage: TEAM_ID [HUB_ID]}"
HUB="${2:-}"
SUBJ="${FUSION_CHALLENGE_NATS_SUBJECT:-gaiaftcl.fusion.challenge.ledger}"
if [[ -z "${NATS_URL:-}" ]] || ! command -v nats >/dev/null 2>&1; then
  echo "REFUSED: set NATS_URL and install nats CLI"
  exit 2
fi
BODY="$(jq -n \
  --arg id "$TEAM" \
  --arg h "$HUB" \
  --arg src "nats_pub" \
  '{
    op: "register_team",
    team_id: $id,
    hub_id: (if $h == "" then null else $h end),
    source: $src
  }' | tr -d '\n')"
NATS_URL="${NATS_URL}" nats pub "$SUBJ" "$BODY"
echo "[fusion_challenge_nats_publish_team] published to $SUBJ team=$TEAM"
