#!/usr/bin/env bash
# Chess Move 3: re-scrape /cell until 11/11 or max rounds; NATS scout poke between rounds.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI="$ROOT/services/gaiaos_ui_web"
export DISCORD_PLAYWRIGHT_PROFILE="${DISCORD_PLAYWRIGHT_PROFILE:-gaiaftcl}"

ROUNDS="${C4_EARTH_LOCK_ROUNDS:-12}"
WAIT_SEC="${C4_EARTH_LOCK_WAIT_SEC:-25}"
NATS_URL="${NATS_URL:-nats://127.0.0.1:4222}"
OUT_JSON="$ROOT/evidence/discord/C4_CELL_EARTH_AUDIT.json"

log() { printf '%s\n' "$*"; }

for ((r = 1; r <= ROUNDS; r++)); do
  log "━━ Planetary gate round $r / $ROUNDS ━━"
  set +e
  (
    cd "$UI"
    C4_CELL_EARTH_AUDIT=1 npx playwright test tests/discord/cell_earth_audit.spec.ts \
      --config=playwright.discord.config.ts --headed
  )
  pw=$?
  set -e
  if [[ ! -f "$OUT_JSON" ]]; then
    log "WARN: missing $OUT_JSON (playwright exit $pw)"
  else
    if python3 -c "import json,sys; d=json.load(open('$OUT_JSON')); sys.exit(0 if d.get('earth_11_11_closed') else 1)"; then
      log "CALORIE: earth 11/11 MOORED locked (round $r)"
      exit 0
    fi
    STALE="$(python3 -c "import json;d=json.load(open('$OUT_JSON'));print(','.join(d.get('stale_patterns')or[])))" 2>/dev/null || true)"
    if [[ -n "$STALE" && "${C4_EARTH_NATS_POKE:-1}" == "1" ]]; then
      log "━━ Scout poke (NATS) stale patterns ━━"
      set +e
      python3 "$ROOT/scripts/publish_earth_scout_poke.py" --nats-url "$NATS_URL" --patterns "$STALE"
      set -e
    fi
  fi
  sleep "$WAIT_SEC"
done

log "PARTIAL: earth not locked 11/11 after $ROUNDS rounds (see $OUT_JSON)"
exit 0
