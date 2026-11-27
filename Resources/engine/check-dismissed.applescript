-- For returned mails the user has had a while to look at: has the user dismissed them? Dismissing = clicking the flag off (the toolbar
-- flag button), or moving/deleting the mail out of the INBOX. When the flag is off, the orange background goes too.
-- Prints one line per dismissed mail: <id>\t<flag cleared|gone>. Skips everything when the INBOX looks empty (Mail still loading).
-- argv: account, then message ids (no angle brackets)
on run argv
	set acctName to item 1 of argv
	set outLines to {}
	tell application "Mail"
		set acct to first account whose name is acctName
		set inboxBox to mailbox "INBOX" of acct
		if (count of messages of inboxBox) > 0 then
			repeat with k from 2 to count of argv
				set wanted to item k of argv
				set found to (every message of inboxBox whose message id is wanted)
				if (count of found) is 0 then
					set end of outLines to wanted & tab & "gone"
				else
					repeat with c in found
						if not (flagged status of c) then
							set background color of c to none
							set end of outLines to wanted & tab & "flag cleared"
							exit repeat
						end if
					end repeat
				end if
			end repeat
		end if
	end tell
	set AppleScript's text item delimiters to linefeed
	return outLines as text
end run
