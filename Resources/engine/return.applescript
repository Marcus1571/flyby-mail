-- "Return" a due mail: copy it from Sent into INBOX, then mark the copy so it cannot be mistaken for new mail:
-- orange flag + orange background + unread. Prints "copied <n>" (n = matching messages now in INBOX, should be 1).
-- Safe against doing it twice: if a copy is already in INBOX it only re-applies the marks.
-- argv: account, messageId (no angle brackets)
on run argv
	set acctName to item 1 of argv
	set wantedId to item 2 of argv
	tell application "Mail"
		set acct to first account whose name is acctName
		set sentBox to my sentMailboxOf(acct)
		set inboxBox to mailbox "INBOX" of acct
		set existing to (every message of inboxBox whose message id is wantedId)
		if (count of existing) is 0 then
			set src to first message of sentBox whose message id is wantedId
			duplicate src to inboxBox
			delay 3 -- the copy is made on the server; give Mail a moment to list it
		end if
		set found to (every message of inboxBox whose message id is wantedId)
		repeat with c in found
			set flag index of c to 1
			set background color of c to orange
			set read status of c to false
		end repeat
		return "copied " & (count of found)
	end tell
end run
