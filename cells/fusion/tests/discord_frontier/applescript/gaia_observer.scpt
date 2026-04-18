-- Persistent observer: front window title hints for CALORIE/CURE/TORSION
-- IMPORTANT: `on idle` only runs when saved as Application in Script Editor with "Stay open after run handler".
-- CLI: use gaia_observer_poll.sh instead.

on idle
	tell application "System Events"
		if not (exists process "Discord") then return 30
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
	return 30
end idle
