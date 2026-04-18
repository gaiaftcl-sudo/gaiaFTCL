#!/usr/bin/env bash
# Chess Move 2: surface Screen Recording prefs + settle (Playwright headed capture).
# Does not grant TCC by itself; reduces "first denial" flakes when permission already granted.
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" 2>/dev/null || true
sleep "${C4_FUSION_VISUAL_SETTLE_SEC:-2}"
# If Terminal/iTerm was frontmost, give Chromium a chance to become visible on retry
osascript -e 'tell application "System Events" to keystroke tab using {command down}' 2>/dev/null || true
exit 0
