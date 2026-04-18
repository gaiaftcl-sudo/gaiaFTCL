#!/bin/bash
# One-shot window-title observer (CLI-friendly). Run from cron or loop externally.
# Usage: ./gaia_observer_poll.sh

osascript <<'APPLESCRIPT'
tell application "System Events"
	if not (exists process "Discord") then return
	tell process "Discord"
		try
			set winTitle to name of front window
			if winTitle contains "CALORIE" or winTitle contains "CURE" then
				display notification winTitle with title "GaiaFTCL Receipt" sound name "Glass"
			end if
			if winTitle contains "TORSION" or winTitle contains "COLLAPSED" then
				display notification winTitle with title "TORSION ALERT" sound name "Basso"
			end if
		end try
	end tell
end tell
APPLESCRIPT
