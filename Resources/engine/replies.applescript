-- Is there an answer to a sent mail? Looks at INBOX messages received after the sent mail and keeps those whose
-- In-Reply-To/References contain its Message-Id and that are not from me and not automatic (bounce, out-of-office).
-- Prints one line per real answer: <fromAddress>   (nothing when unanswered). Only the headers of the few newer messages are read.
-- argv: account, messageId (no angle brackets), ageSeconds of the sent mail
on run argv
	set acctName to item 1 of argv
	set wantedId to item 2 of argv
	set sentAge to (item 3 of argv) as integer
	set nowDate to current date
	set outLines to {}
	tell application "Mail"
		set acct to first account whose name is acctName
		set myAddresses to email addresses of acct
		set inboxBox to mailbox "INBOX" of acct
		set newer to (every message of inboxBox whose date received > (nowDate - sentAge))
		repeat with m in newer
			set h to all headers of m
			set refs to (my headerValue(h, "In-Reply-To:")) & " " & (my headerValue(h, "References:"))
			if refs contains wantedId then
				set autoKind to (my headerValue(h, "Auto-Submitted:")) & (my headerValue(h, "X-Autoreply:")) & (my headerValue(h, "X-Autorespond:"))
				set prec to my headerValue(h, "Precedence:")
				set fromAddr to extract address from (sender of m)
				set isMine to false
				repeat with a in myAddresses
					if fromAddr is (contents of a) then set isMine to true
				end repeat
				set isAuto to (autoKind contains "auto") or (prec contains "bulk") or (prec contains "auto_reply") or (prec contains "junk")
				if not isMine and not isAuto and not (fromAddr starts with "mailer-daemon") and not (fromAddr starts with "postmaster") then
					set end of outLines to fromAddr
				end if
			end if
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	return outLines as text
end run
