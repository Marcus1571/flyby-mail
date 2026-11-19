-- "Return" a due mail: copy it from Sent into INBOX, then mark the copy so it cannot be mistaken for new mail:
-- orange flag + orange background + unread. Prints "copied <n> flagged=<bool> color=<color>" read back from Mail.
-- Safe against doing it twice: if a copy is already in INBOX it is not copied again, only re-marked.
-- Mail replaces the fresh copy when it syncs with the server, and the replacement can come back without the flag
-- (seen live: colour stayed, flag was lost), so the marks are applied, read back, and only trusted once they held on two
-- checks in a row, three seconds apart.
-- argv: account, messageId (no angle brackets)
on run argv
	set acctName to item 1 of argv
	set wantedId to item 2 of argv
	tell application "Mail"
		set acct to first account whose name is acctName
		set sentBox to my sentMailboxOf(acct)
		set inboxBox to mailbox "INBOX" of acct
		if (count of (every message of inboxBox whose message id is wantedId)) is 0 then
			set src to first message of sentBox whose message id is wantedId
			duplicate src to inboxBox
		end if
		set holds to 0
		repeat with attempt from 1 to 10
			delay 3
			set found to (every message of inboxBox whose message id is wantedId)
			if (count of found) > 0 then
				set allMarked to true
				repeat with c in found
					if not (flagged status of c) or (background color of c) is not orange then
						set flag index of c to 1
						set background color of c to orange
						set read status of c to false
						set allMarked to false
					end if
				end repeat
				if allMarked then
					set holds to holds + 1
					if holds >= 2 then exit repeat
				else
					set holds to 0
				end if
			end if
		end repeat
		set found to (every message of inboxBox whose message id is wantedId)
		set report to "copied " & (count of found)
		repeat with c in found
			set report to report & " flagged=" & (flagged status of c) & " color=" & (background color of c)
		end repeat
		return report
	end tell
end run
