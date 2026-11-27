-- The mail currently selected in Mail (the first one when several are): account name, Message-Id (no angle brackets), subject and sender, tab separated.
-- Prints nothing when nothing is selected. Never starts Mail: the Swift side only calls this while Mail is running.
on run argv
	tell application "Mail"
		set picked to selection
		if (count of picked) is 0 then return ""
		set m to item 1 of picked
		set boxOfMail to mailbox of m
		set acctName to name of (account of boxOfMail)
		set subj to subject of m
		if subj is "" then set subj to "(no subject)"
		return acctName & tab & (message id of m) & tab & subj & tab & (sender of m)
	end tell
end run
