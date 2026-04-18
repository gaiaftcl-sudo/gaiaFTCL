#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI="$ROOT/services/gaiaos_ui_web"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$ROOT/evidence/discord/dual_user/$TS"
WITNESS_JSON="$OUT_DIR/DUAL_USER_WITNESS.json"
REPORT_MD="$OUT_DIR/DUAL_USER_VALIDATION_$TS.md"

mkdir -p "$OUT_DIR"

log() {
  printf '%s\n' "$*" | tee -a "$REPORT_MD"
}

DEFAULT_CHANNEL_URL="https://discord.com/channels/1487775674356990064/1487775675665354835"
if [[ -z "${DISCORD_MEMBRANE_CHANNEL_URL:-}" ]]; then
  export DISCORD_MEMBRANE_CHANNEL_URL="$DEFAULT_CHANNEL_URL"
fi
if [[ -z "${DISCORD_OWL_CHANNEL_URL:-}" ]]; then
  export DISCORD_OWL_CHANNEL_URL="${DISCORD_MEMBRANE_CHANNEL_URL}"
fi
if [[ -z "${DISCORD_USER_A_CHANNEL_URL:-}" ]]; then
  export DISCORD_USER_A_CHANNEL_URL="${DISCORD_OWL_CHANNEL_URL}"
fi
if [[ -z "${DISCORD_USER_B_CHANNEL_URL:-}" ]]; then
  export DISCORD_USER_B_CHANNEL_URL="${DISCORD_MEMBRANE_CHANNEL_URL}"
fi
# Phase 1 → hook → phase 2: real Fusion/NATS publish when available (see scripts/dual_user_phase2_hook.sh).
export DUAL_USER_PHASE2_HOOK="${DUAL_USER_PHASE2_HOOK:-bash $ROOT/scripts/dual_user_phase2_hook.sh}"

log "# GaiaFTCL Dual-User Validation"
log "- ts_utc: $TS"
log "- out_dir: $OUT_DIR"
log "- owl_channel: $DISCORD_OWL_CHANNEL_URL"
log "- observer_channel: ${DISCORD_MEMBRANE_CHANNEL_URL:-"(default)"}"
log "- user_a_channel: ${DISCORD_USER_A_CHANNEL_URL}"
log "- user_b_channel: ${DISCORD_USER_B_CHANNEL_URL}"
log "- phase2_hook: ${DUAL_USER_PHASE2_HOOK}"
log ""

log "## No-simulation gate"
bash "$ROOT/services/discord_frontier/check_no_simulation.sh" | tee -a "$REPORT_MD"

log ""
log "## Command force-refresh gate"
python3 "$ROOT/scripts/refresh_discord_commands.py" \
  --guild "${DISCORD_GUILD_ID:-1487775674356990064}" \
  --head-ip "${HEAD_IP:-77.42.85.60}" \
  --ssh-key "${SSH_IDENTITY_FILE:-$HOME/.ssh/ftclstack-unified}" | tee -a "$REPORT_MD"

log ""
log "## Witness preflight"
bash "$ROOT/scripts/playwright_discord_witness_preflight.sh" gaiaftcl | tee -a "$REPORT_MD"
bash "$ROOT/scripts/playwright_discord_witness_preflight.sh" face_of_madness | tee -a "$REPORT_MD"

log ""
log "## Dual-user Playwright run"
(
  cd "$UI"
  DUAL_USER_OUT_DIR="$OUT_DIR" npm run test:e2e:discord:dual-user
) | tee -a "$REPORT_MD"

if [[ ! -f "$WITNESS_JSON" ]]; then
  echo "REFUSED: witness file missing: $WITNESS_JSON" >&2
  exit 2
fi

log ""
log "## Hard invariant gate"
python3 - "$WITNESS_JSON" <<'PY' | tee -a "$REPORT_MD"
import json, sys
p = sys.argv[1]
data = json.load(open(p, "r", encoding="utf-8"))
c = data.get("criteria", {})
required = [
    ("state_convergence_release_id", bool(c.get("state_convergence_release_id"))),
    ("source_diversity", bool(c.get("source_diversity"))),
    ("convergence_lt_2s", bool(c.get("convergence_lt_2s"))),
]
bad = [k for k, ok in required if not ok]
print(f"WITNESS: {p}")
print(f"user_a_source={data.get('user_a', {}).get('source')}")
print(f"user_b_source={data.get('user_b', {}).get('source')}")
print(f"user_a_release_id={data.get('user_a', {}).get('release_id')}")
print(f"user_b_release_id={data.get('user_b', {}).get('release_id')}")
print(f"convergence_ms={data.get('convergence_ms')}")
if bad:
    print("REFUSED: " + ", ".join(bad))
    raise SystemExit(2)
print("CALORIE: dual-user hard invariants passed")
PY

log ""
log "STATE: CALORIE"
log "WITNESS_JSON: $WITNESS_JSON"
log "REPORT_MD: $REPORT_MD"

