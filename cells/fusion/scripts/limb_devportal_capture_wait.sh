#!/usr/bin/env bash
# Poll for discord-forest fragment after Terminal-launched capture (no Founder messaging).
set -euo pipefail
OUT="${DISCORD_DEVPORTAL_OUT:-$HOME/.playwright-discord/discord-forest.captured.fragment.env}"
MAX_SEC="${DISCORD_DEVPORTAL_WAIT_SEC:-900}"
STEP="${DISCORD_DEVPORTAL_WAIT_STEP_SEC:-5}"
deadline=$((SECONDS + MAX_SEC))
echo "limb_devportal_capture_wait: watching $OUT (max ${MAX_SEC}s, step ${STEP}s)"
while [ "$SECONDS" -lt "$deadline" ]; do
  if [ -f "$OUT" ]; then
    n="$(grep -cE '^DISCORD_[A-Z0-9_]+=[^[:space:]]{20,}' "$OUT" 2>/dev/null || true)"
    if [ "${n:-0}" -ge 1 ]; then
      echo "CALORIE: $OUT has $n token line(s)"
      wc -l "$OUT"
      exit 0
    fi
  fi
  sleep "$STEP"
done
echo "REFUSED: timeout — no captured DISCORD_*=token lines in $OUT" >&2
exit 1
