#!/usr/bin/env bash
# Open macOS Terminal.app and run a command under services/gaiaos_ui_web (Chrome GUI path).
# Default: Discord Developer Portal DOM token capture.
# Usage:
#   bash cells/fusion/scripts/run_in_terminal_mac.sh
#   bash cells/fusion/scripts/run_in_terminal_mac.sh npm run playwright:devportal:codegen:gaiaftcl
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "REFUSED: Terminal.app is macOS-only; run npm from your shell on this OS." >&2
  exit 1
fi

GAIA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="$GAIA_ROOT/services/gaiaos_ui_web"
if [ ! -d "$WEB" ]; then
  echo "REFUSED: missing $WEB" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  set -- npm run playwright:devportal:capture
fi

# Stable path — do not use mktemp+trap (Terminal opens async; file would be deleted first).
LAUNCH_DIR="${HOME}/.playwright-discord"
mkdir -p "$LAUNCH_DIR"
TMP="${GAIAFTCL_TERMINAL_LAUNCH_SCRIPT:-$LAUNCH_DIR/last_terminal_launch.sh}"

{
  echo "#!/usr/bin/env bash"
  echo "# Rewritten by run_in_terminal_mac.sh — safe to delete."
  echo "set -euo pipefail"
  echo "cd $(printf '%q' "$WEB")"
  echo "unset CI 2>/dev/null || true"
  echo "export PATH=\"/usr/local/bin:/opt/homebrew/bin:\$PATH\""
  echo "exec $(printf '%q ' "$@")"
} >"$TMP"
chmod 700 "$TMP"

# AppleScript: run wrapper in a new Terminal tab/window
osascript <<OSA
tell application "Terminal"
  activate
  do script "bash $(printf '%q' "$TMP")"
end tell
OSA

echo "Launched Terminal.app → bash $TMP"
echo "  cwd: $WEB"
echo "  cmd: $*"
