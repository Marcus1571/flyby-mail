-- Take the marks off a returned mail (you dealt with it): no flag, no background colour. The mail itself stays where it is.
-- Prints "unmarked <n>".
-- argv: account, messageId (no angle brackets)
on run argv
	set acctName to item 1 of argv
	set wantedId to item 2 of argv
	tell application "Mail"
		set acct to first account whose name is acctName
		set inboxBox to mailbox "INBOX" of acct
		set found to (every message of inboxBox whose message id is wantedId)
		repeat with c in found
			set flagged status of c to false
			set background color of c to none
		end repeat
		return "unmarked " & (count of found)
	end tell
end run
