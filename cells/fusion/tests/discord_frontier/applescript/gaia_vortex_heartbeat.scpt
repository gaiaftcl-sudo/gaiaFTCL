-- Background heartbeat: poll claim count + optional torsion endpoint.
-- CLI `osascript` does NOT run `on idle`. Use gaia_vortex_heartbeat_daemon.sh for terminal use.
-- For App bundle: save in Script Editor as Application, enable "Stay open after run handler",
--   and set environment PHASE6_APPLE_DIR to this directory (LaunchAgent / open -a).

property lastReceiptCount : 0
property appleDir : ""

on run argv
	if (count of argv) > 0 then
		set appleDir to item 1 of argv
	else
		try
			set appleDir to (system attribute "PHASE6_APPLE_DIR") as text
		end try
	end if
	if appleDir is "" then error "Set PHASE6_APPLE_DIR or pass POSIX path to applescript/ as argv[1]"
end run

on idle
	set countScript to quoted form of (appleDir & "/curl_claims_count.sh")
	set torsionScript to quoted form of (appleDir & "/curl_torsion_state.sh")
	try
		set rawResult to do shell script countScript without altering line endings
		set newCount to rawResult as integer
	on error
		set newCount to 0
	end try
	
	if newCount > lastReceiptCount then
		set receiptDelta to newCount - lastReceiptCount
		display notification (receiptDelta as text) & " new receipt(s) on the wall" with title "GaiaFTCL — Calories or Cures" sound name "Glass"
		set lastReceiptCount to newCount
	end if
	
	try
		set torsionResult to do shell script torsionScript without altering line endings
		if torsionResult is not "NOHARM" and (length of torsionResult) > 0 then
			display notification "System state: " & torsionResult with title "TORSION ALERT — GaiaFTCL" sound name "Basso"
		end if
	end try
	
	return 30
end idle
