#!/usr/bin/env bash
# Mac limb: bring Discord.app forward after you deploy /gaia-topology (AppleScript).
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS only."
  exit 0
fi
osascript <<'APPLESCRIPT'
tell application "Discord" to activate
delay 0.5
APPLESCRIPT
echo "Discord activated. In your server, type: /gaia-topology (dry_run false) after the membrane bot is online with Manage Channels."
