#!/usr/bin/env bash
# Discord web smoke tests (Playwright). No secrets in repo — optional auth via env.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PW_DIR="${REPO_ROOT}/tests/discord_frontier/playwright"

echo "=== DISCORD MEMBRANE PLAYWRIGHT ==="
echo "Dir: ${PW_DIR}"
cd "$PW_DIR"

if [[ ! -f package.json ]]; then
  echo "BLOCKED: package.json missing at ${PW_DIR}"
  exit 2
fi

npm install --silent
npx playwright install chromium
npx playwright test --reporter=list "$@"
echo "OK: Playwright suite finished (exit $?)"
exit 0
