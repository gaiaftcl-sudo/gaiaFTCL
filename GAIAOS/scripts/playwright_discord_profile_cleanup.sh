#!/usr/bin/env bash
# Remove Next dev lock + Chromium profile locks under .playwright-discord (prevents "profile in use" / stale lock).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI="$ROOT/services/gaiaos_ui_web"

rm -f "$UI/.next/dev/lock" 2>/dev/null || true
# Turbopack / alternate layouts
find "$UI/.next" -name "lock" -type f 2>/dev/null | while read -r f; do
  case "$f" in
    */dev/*) rm -f "$f" && echo "removed $f" ;;
  esac
done || true

PD="$UI/.playwright-discord"
if [[ -d "$PD" ]]; then
  find "$PD" -type f \( -name "SingletonLock" -o -name "SingletonSocket" -o -name "lockfile" \) -print -delete 2>/dev/null || true
  echo "[playwright_discord_profile_cleanup] cleaned Chromium locks under $PD"
else
  echo "[playwright_discord_profile_cleanup] no $PD yet"
fi

echo "[playwright_discord_profile_cleanup] done"
