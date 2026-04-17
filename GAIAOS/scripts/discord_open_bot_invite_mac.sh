#!/usr/bin/env bash
# Open Discord OAuth2 URL so the bot is installed with slash-command scope.
# Limb runs this on the Founder Mac; do not hand the URL back as "your homework".
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PW_DIR="$REPO_ROOT/services/gaiaos_ui_web"

CID="${DISCORD_APPLICATION_ID:-${DISCORD_APP_CLIENT_ID:-}}"
GID="${DISCORD_GUILD_ID:-}"
PERMS="${DISCORD_BOT_PERMISSIONS:-}"

if [ -z "$CID" ]; then
  echo "Set DISCORD_APPLICATION_ID (preferred) or DISCORD_APP_CLIENT_ID" >&2
  exit 1
fi

URL="https://discord.com/api/oauth2/authorize?client_id=${CID}&scope=bot%20applications.commands"
if [ -n "$PERMS" ]; then
  URL="${URL}&permissions=${PERMS}"
fi
if [ -n "$GID" ]; then
  URL="${URL}&guild_id=${GID}&disable_guild_select=true"
fi

echo "$URL"
if [ ! -d "$PW_DIR" ]; then
  echo "REFUSED: Playwright workspace missing: $PW_DIR" >&2
  exit 2
fi

cd "$PW_DIR"
npx playwright install chromium >/dev/null 2>&1 || true
npx playwright open --browser chromium "$URL"
