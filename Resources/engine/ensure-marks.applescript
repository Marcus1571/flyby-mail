-- Make sure returned mails still carry their marks (orange flag + orange background). Mail can lose the flag when it refreshes the
-- inbox from the server (seen live: two mails returned in the same tick, the first one lost its flag). Re-applies only what is missing and
-- never touches the read state. Prints one line per id: <id> flagged=<bool> color=<color>.
-- argv: account, then message ids (no angle brackets)
on run argv
	set acctName to item 1 of argv
	set outLines to {}
	tell application "Mail"
		set acct to first account whose name is acctName
		set inboxBox to mailbox "INBOX" of acct
		repeat with k from 2 to count of argv
			set wanted to item k of argv
			set found to (every message of inboxBox whose message id is wanted)
			repeat with c in found
				if not (flagged status of c) then set flag index of c to 1
				if (background color of c) is not orange then set background color of c to orange
			end repeat
			delay 1
			set found to (every message of inboxBox whose message id is wanted)
			repeat with c in found
				set end of outLines to wanted & " flagged=" & (flagged status of c) & " color=" & (background color of c)
			end repeat
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	return outLines as text
end run
