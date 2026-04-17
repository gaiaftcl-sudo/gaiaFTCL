#!/usr/bin/env bash
# Playwright: Discord Developer Portal for application (default DISCORD_APPLICATION_ID).
# Auth: DISCORD_DEV_PORTAL_STORAGE_STATE=./discord-devportal-state.json (recommended)
#    or DISCORD_DEV_PORTAL_EMAIL + DISCORD_DEV_PORTAL_PASSWORD (2FA will skip).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PW_DIR="${REPO_ROOT}/tests/discord_frontier/playwright"

export DISCORD_APPLICATION_ID="${DISCORD_APPLICATION_ID:-1487798260339966023}"

cd "$PW_DIR"
npm install --silent
npx playwright install chromium
echo "=== Developer Portal Playwright (app $DISCORD_APPLICATION_ID) ==="
npx playwright test discord_developer_portal.spec.ts --reporter=list "$@"
echo "Screenshots + summary under: $REPO_ROOT/evidence/discord_closure/dev_portal/"
