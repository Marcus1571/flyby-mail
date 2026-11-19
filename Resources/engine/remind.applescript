-- "Return" a due mail by sending the user a REMINDER MAIL from their own account to their own address. A copy of the original would keep
-- its old date and sit buried in the inbox; a new mail arrives dated now: at the top, unread, with a push notification on the phone.
-- The body says who was written to, when, and quotes the original, plus a message:// link that opens the original in Mail.
-- Safe against doing it twice: if a reminder with the same subject was already sent in the last 6 hours it is reused, not sent again.
-- Prints "reminder <message-id of the reminder>" (read from the Sent copy), or "reminder-not-found".
-- argv: account, messageId of the original (no angle brackets)
on run argv
	set acctName to item 1 of argv
	set wantedId to item 2 of argv
	tell application "Mail"
		set acct to first account whose name is acctName
		set sentFolder to my sentMailboxOf(acct)
		set src to first message of sentFolder whose message id is wantedId
		set origSubject to subject of src
		if origSubject is "" then set origSubject to "(no subject)"
		if (length of origSubject) > 120 then set origSubject to (text 1 thru 120 of origSubject) & "…"
		set remSubject to "FlyBy: nobody replied to “" & origSubject & "”"
		set cutoff to (current date) - 6 * hours
		if (count of (every message of sentFolder whose subject is remSubject and date sent > cutoff)) is 0 then
			set toList to ""
			repeat with r in (to recipients of src)
				set toList to toList & (address of r) & " "
			end repeat
			set origText to content of src
			if (length of origText) > 3000 then set origText to (text 1 thru 3000 of origText) & "…"
			set bodyText to "Nobody has replied to this mail yet." & return & return & "To: " & toList & return & "Sent: " & ((date sent of src) as string) & return & "Subject: " & origSubject & return & return & "Open the original in Mail: message://%3C" & wantedId & "%3E" & return & return & "— the original message —" & return & origText
			set addrList to email addresses of acct
			set addr to item 1 of addrList
			set msg to make new outgoing message with properties {subject:remSubject, content:bodyText, visible:false}
			tell msg
				set sender to (full name of acct) & " <" & addr & ">"
				make new to recipient at end of to recipients with properties {address:addr}
			end tell
			send msg
		end if
		repeat with attempt from 1 to 15
			delay 2
			set sentCopies to (every message of sentFolder whose subject is remSubject and date sent > cutoff)
			if (count of sentCopies) > 0 then return "reminder " & (message id of item 1 of sentCopies)
		end repeat
	end tell
	return "reminder-not-found"
end run
