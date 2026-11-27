-- "Return" a due mail by sending the user a REMINDER MAIL from their own account to their own address. A copy of the original would keep
-- its old date and sit buried in the inbox; a new mail arrives dated now: at the top, unread, with a push notification on the phone.
-- The body says who was written to, when, and quotes the original, plus a message:// link that opens the original in Mail.
-- Safe against doing it twice, from any machine: a reminder in Sent or Trash with the same subject whose body carries this mail's Message-Id link (of ANY age) is reused, not sent again.
-- The Sent copy of the reminder is moved to the account's Trash once its id is read (0.3.2): the reminder belongs in the inbox, not among the mails you sent.
-- Trash still holds it for the duplicate check. Gmail keeps it (one message for Inbox and Sent there, see trashMailboxOf).
-- Prints "reminder <message-id of the reminder>" (read from the Sent copy), or "reminder-not-found".
-- argv: account, messageId of the original (no angle brackets), optional switch "1"/"0" (sent mails), optional source "received" (a mail the user picked in
-- the Inbox: the original is looked up in the account's mailboxes, not in Sent), optional "0" when the mail was sent with "only if nobody replies" OFF (the reminder then
-- must not claim that nobody replied: someone may well have)
on run argv
	set acctName to item 1 of argv
	set wantedId to item 2 of argv
	set onlyIfNoReply to true
	if (count of argv) > 2 and item 3 of argv is "0" then set onlyIfNoReply to false
	tell application "Mail"
		set acct to first account whose name is acctName
		set sentFolder to my sentMailboxOf(acct)
		set trashBox to my trashMailboxOf(acct)
		set isReceived to ((count of argv) > 3 and item 4 of argv is "received")
		set src to missing value
		if isReceived then
			-- a mail the user picked: usually still in the Inbox, else look through the account's other mailboxes
			set boxes to {mailbox "INBOX" of acct} & (mailboxes of acct)
			repeat with bx in boxes
				try
					set hits to (every message of bx whose message id is wantedId)
					if (count of hits) > 0 then
						set src to item 1 of hits
						exit repeat
					end if
				end try
			end repeat
			if src is missing value then return "original-missing"
		else
			set src to first message of sentFolder whose message id is wantedId
		end if
		set origSubject to subject of src
		if origSubject is "" then set origSubject to "(no subject)"
		if (length of origSubject) > 120 then set origSubject to (text 1 thru 120 of origSubject) & "…"
		set remSubject to "FlyBy: nobody replied to “" & origSubject & "”"
		if not onlyIfNoReply then set remSubject to "FlyBy: reminder for “" & origSubject & "”"
		set cutoff to (current date) - 6 * hours
		set existing to missing value
		set lookIn to {sentFolder}
		if trashBox is not missing value then set end of lookIn to trashBox
		repeat with bx in lookIn
			repeat with m in (every message of bx whose subject is remSubject)
				if (content of m) contains wantedId then
					set existing to contents of m -- the message itself: m is only a pointer into the list, and move fails silently on it
					exit repeat
				end if
			end repeat
			if existing is not missing value then exit repeat
		end repeat
		if existing is not missing value then
			set remId to message id of existing
			my toTrash(existing, trashBox)
			return "reminder " & remId
		end if
		if true then
			set toList to ""
			repeat with r in (to recipients of src)
				set toList to toList & (address of r) & " "
			end repeat
			set whoLine to "To: " & toList & return & "Sent: " & ((date sent of src) as string)
			if isReceived then set whoLine to "From: " & (sender of src) & return & "Received: " & ((date received of src) as string)
			set origText to content of src
			if (length of origText) > 3000 then set origText to (text 1 thru 3000 of origText) & "…"
			set openLine to "Nobody has replied to this mail yet."
			if isReceived then set openLine to "Nobody has replied to this conversation since you asked to be reminded."
			if not onlyIfNoReply then set openLine to "This is the reminder you asked for. It comes back whether or not someone replied."
			set bodyText to openLine & return & return & whoLine & return & "Subject: " & origSubject & return & return & "Open the original in Mail: message://%3C" & wantedId & "%3E" & return & return & "— the original message —" & return & origText
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
			if (count of sentCopies) > 0 then
				set remId to message id of item 1 of sentCopies
				repeat with c in sentCopies
					my toTrash(contents of c, trashBox)
				end repeat
				return "reminder " & remId
			end if
		end repeat
	end tell
	return "reminder-not-found"
end run

-- Moves a reminder's Sent copy to Trash; leaves it (Gmail, no Trash found, already in Trash) when that is not possible or not needed.
on toTrash(m, trashBox)
	if trashBox is missing value then return
	tell application "Mail"
		try
			if (name of (mailbox of m)) is not (name of trashBox) then move m to trashBox
		end try
	end tell
end toTrash
