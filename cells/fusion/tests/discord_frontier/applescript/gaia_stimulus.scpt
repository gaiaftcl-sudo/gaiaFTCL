-- Phase 6 S4 stimulus: Quick Switcher (⌘K) → channel name → message + Return
-- Usage: osascript gaia_stimulus.scpt "owl-protocol" "/moor"
-- Requires: Discord running, Accessibility for Terminal/iTerm, en_US keyboard layout

on run argv
	if (count of argv) < 2 then error "Usage: osascript gaia_stimulus.scpt <channelName> <messageText>"
	set channelName to item 1 of argv
	set messageText to item 2 of argv
	
	tell application "Discord" to activate
	delay 1.5
	
	tell application "System Events"
		tell process "Discord"
			keystroke "k" using {command down}
			delay 0.7
			keystroke channelName
			delay 0.8
			keystroke return
			delay 1.5
			keystroke messageText
			delay 0.3
			keystroke return
		end tell
	end tell
	
	return "STIMULUS_SENT: " & channelName & " | " & messageText
end run
