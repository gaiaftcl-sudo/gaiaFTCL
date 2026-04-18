#!/usr/bin/env bash
# Paste-friendly lines for a Discord game room (Fusion global challenge + mesh hooks).
# Same API URLs as Fusion UI "Mesh & Discord" panel (s4-projection embeds mesh_operator_spine).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/deploy/fusion_mesh/config/global_sovereign_challenge_s4.json"
PORT="${FUSION_UI_PORT:-8910}"
UI_BASE="${FUSION_SOVEREIGN_UI_URL:-http://127.0.0.1:${PORT}}"
UI_BASE="${UI_BASE%/}"

if ! command -v jq >/dev/null 2>&1; then
  echo "REFUSED: jq required"
  exit 2
fi

[[ -f "$CFG" ]] || { echo "REFUSED: missing $CFG"; exit 2; }

TITLE="$(jq -r '.title // "Global Sovereign Challenge"' "$CFG")"
CAP="$(jq -r '.challenger_pool_cap // 50' "$CFG")"
TRIG="$(jq -r '.revenue_trigger_ledger_eur // 0' "$CFG")"
CYCLE="$(jq -r '.cycle_witness_target // 1000000' "$CFG")"
DISC="$(jq -r '.discord.game_room_note // ""' "$CFG")"

echo "━━ $TITLE ━━"
echo "Fusion S4 console: ${UI_BASE}/fusion-s4"
echo "S4 projection (full): ${UI_BASE}/api/fusion/s4-projection"
echo "Mesh operator spine (same JSON as UI panel): ${UI_BASE}/api/fusion/mesh-operator-spine"
echo "JSON digest (when Next is up): ${UI_BASE}/api/fusion/global-challenge-digest"
echo "Ledger read: ${UI_BASE}/api/fusion/challenge-ledger (POST needs FUSION_CHALLENGE_LEDGER_SECRET)"
echo "Challenger cap (S⁴ config): ${CAP} teams · cycle witness target: ${CYCLE}"
echo "Revenue trigger (ledger, C⁴): ${TRIG} EUR — reported only from fusion_challenge_ledger_receipt.json"
echo "Moor: deploy/mac_cell_mount/README_MEMBRANE.md · invite: scripts/discord_open_bot_invite_mac.sh"
echo "Slash: $(jq -r '.discord.slash_command_hints | join(" · ")' "$CFG")"
echo "Deployed bots: set FUSION_SOVEREIGN_UI_URL to reachable host; DISCORD_REQUIRE_PUBLIC_FUSION_UI=1 refuses localhost."
echo ""
echo "$DISC"
echo ""
echo "Multi-language CTA: deploy/fusion_mesh/docs/GLOBAL_SOVEREIGN_CHALLENGE_CTA.md"

if [[ -n "${FUSION_DIGEST_SAVE_EVIDENCE:-}" ]]; then
  EVD="$ROOT/evidence/fusion_control/discord_mesh_digest"
  mkdir -p "$EVD"
  TS="$(date -u +%Y%m%dT%H%M%SZ)"
  JSONL="$EVD/digest_manifest_${TS}.jsonl"
  : >"$JSONL"
  for path in global-challenge-digest mesh-operator-spine "s4-projection"; do
    out="$EVD/${path//\//_}_${TS}.json"
    if curl -sfS "${UI_BASE}/api/fusion/${path}" -o "$out"; then
      echo "Saved $out"
      h="$(shasum -a 256 "$out" | awk '{print $1}')"
      jq -nc \
        --arg schema "gaiaftcl_fusion_digest_manifest_line_v1" \
        --arg p "$out" \
        --arg h "$h" \
        --arg ts "$TS" \
        --arg api "GET /api/fusion/${path}" \
        '{schema:$schema,artifact_path:$p,sha256:$h,ts_utc:$ts,api:$api}' >>"$JSONL"
    else
      echo "SKIP (curl failed): ${UI_BASE}/api/fusion/${path}"
    fi
  done
  if [[ -s "$JSONL" ]]; then
    echo "JSONL manifest: $JSONL"
  fi
fi
