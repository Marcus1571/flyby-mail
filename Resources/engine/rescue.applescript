-- Rescue replies from Junk: an answer to a tracked mail can be filed as junk by the provider (Yahoo Bulk, Gmail Spam) or by Mail itself.
-- Looks once at the messages that reached ANY account's junk mailbox in the last <sinceAge> seconds; for each real reply (In-Reply-To/References
-- contains a tracked id, not from me, not automatic) it clears the junk status and moves it back to the Inbox of its own account.
-- Prints one line per rescued reply: <trackedId>TAB<fromAddress>TAB<accountName>
-- argv: sinceAgeSeconds, then tracked message ids (no angle brackets)
on run argv
	set sinceAge to (item 1 of argv) as integer
	set nowDate to current date
	set outLines to {}
	tell application "Mail"
		set newer to (every message of junk mailbox whose date received > (nowDate - sinceAge))
		repeat with m in newer
			set h to all headers of m
			set refs to (my headerValue(h, "In-Reply-To:")) & " " & (my headerValue(h, "References:"))
			set hit to ""
			repeat with k from 2 to count of argv
				if refs contains (item k of argv) then set hit to item k of argv
			end repeat
			if hit is not "" then
				set autoKind to (my headerValue(h, "Auto-Submitted:")) & (my headerValue(h, "X-Autoreply:")) & (my headerValue(h, "X-Autorespond:"))
				set prec to my headerValue(h, "Precedence:")
				set fromAddr to extract address from (sender of m)
				set acct to account of (mailbox of m)
				set myAddresses to email addresses of acct
				set isMine to false
				repeat with a in myAddresses
					if fromAddr is (contents of a) then set isMine to true
				end repeat
				set isAuto to (autoKind contains "auto") or (prec contains "bulk") or (prec contains "auto_reply") or (prec contains "junk")
				if not isMine and not isAuto and not (fromAddr starts with "mailer-daemon") and not (fromAddr starts with "postmaster") then
					set junk mail status of m to false
					move m to (mailbox "INBOX" of acct)
					set end of outLines to hit & tab & fromAddr & tab & (name of acct)
				end if
			end if
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	return outLines as text
end run
