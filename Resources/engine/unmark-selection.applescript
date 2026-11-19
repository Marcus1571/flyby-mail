-- Menu action "Clear marks on selected mail": removes flag and background colour from the mails currently selected in Mail, but ONLY those
-- that FlyBy returned (their ids are the arguments), never from the user's other mails. Prints the ids it cleared, one per line.
-- argv: message ids of the returned mails
on run argv
	set doneIds to {}
	tell application "Mail"
		set picked to selection
		repeat with m in picked
			set mid to message id of m
			if argv contains mid then
				set flagged status of m to false
				set background color of m to none
				if doneIds does not contain mid then set end of doneIds to mid
			end if
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	return doneIds as text
end run
