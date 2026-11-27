-- Menu action "Mark selected mail as Not Junk": clears the junk status of the mails selected in Mail and, when one sits in a junk
-- mailbox (Junk, Bulk, Spam), moves it to the Inbox of its own account. Prints how many mails it changed.
on run argv
	set n to 0
	tell application "Mail"
		set picked to selection
		repeat with m in picked
			set changed to false
			if junk mail status of m then
				set junk mail status of m to false
				set changed to true
			end if
			set acct to account of (mailbox of m)
			set boxName to name of (mailbox of m)
			if boxName is in {"Junk", "Junk E-mail", "Junk Email", "Bulk", "Spam", "Bulk Mail"} then
				move m to (mailbox "INBOX" of acct)
				set changed to true
			end if
			if changed then set n to n + 1
		end repeat
	end tell
	return n as text
end run
