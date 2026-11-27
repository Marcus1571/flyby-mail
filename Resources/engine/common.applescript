-- Shared helpers, pasted at the top of every engine script by the Swift engine (osascript cannot import files).
-- AppleScript names are case-insensitive: never name a variable inbox/Inbox/sent... (they are Mail properties).
on headerValue(allHeaders, wanted)
	-- returns the value of one header (unfolded), or "" when absent
	set found to ""
	set grabbing to false
	repeat with ln in paragraphs of allHeaders
		set t to contents of ln
		if grabbing then
			if t starts with " " or t starts with tab then
				set found to found & " " & t
			else
				return found
			end if
		else if t starts with wanted then
			set found to text ((length of wanted) + 1) thru -1 of t
			set grabbing to true
		end if
	end repeat
	return found
end headerValue

on sentMailboxOf(acct)
	tell application "Mail"
		repeat with candidate in {"Sent", "Sent Messages", "Sent Items", "Sent Mail", "Inviati", "Posta inviata", "Messaggi inviati"}
			try
				return mailbox (contents of candidate) of acct
			end try
		end repeat
	end tell
	return missing value
end sentMailboxOf

-- The account's Trash, or missing value. Gmail answers missing value on purpose: there the Sent copy of a mail to yourself is the
-- SAME message as the inbox copy (labels, not folders), so trashing it would take the reminder out of the inbox too.
on trashMailboxOf(acct)
	tell application "Mail"
		try
			set host to server name of acct
			if host contains "gmail" or host contains "googlemail" then return missing value
		end try
		repeat with candidate in {"Trash", "Deleted Messages", "Deleted Items", "Bin", "Cestino", "Posta eliminata"}
			try
				return mailbox (contents of candidate) of acct
			end try
		end repeat
	end tell
	return missing value
end trashMailboxOf
