-- Spike test 2, step 1 (READ ONLY): list the X-FlyBy-tagged mails in an account's Sent mailbox, whether they are due,
-- and whether a reply (In-Reply-To = the sent Message-Id) is in the inbox. Prints only: message-id, due epoch, due?, replies.
-- Usage: osascript scripts/spike-scan.applescript "Yahoo!"
on headerValue(allHeaders, wanted)
	repeat with ln in paragraphs of allHeaders
		set t to contents of ln
		if t starts with wanted then return text ((length of wanted) + 1) thru -1 of t
	end repeat
	return ""
end headerValue

on run argv
	set acctName to item 1 of argv
	set nowEpoch to (do shell script "date +%s") as integer
	set out to {}
	tell application "Mail"
		set acct to first account whose name is acctName
		set sentFolder to mailbox "Sent" of acct
		set inboxBox to mailbox "INBOX" of acct
		set recentIn to (messages of inboxBox whose date received > ((current date) - 7 * days))
		repeat with m in (messages of sentFolder)
			set h to all headers of m
			set fly to my headerValue(h, "X-Flyby:")
			if fly is not "" then
				set mid to my headerValue(h, "Message-Id:")
				set dueEpoch to 0
				set AppleScript's text item delimiters to "due="
				set parts to text items of fly
				if (count of parts) > 1 then
					set AppleScript's text item delimiters to ";"
					set dueEpoch to (first text item of (item 2 of parts)) as integer
				end if
				set AppleScript's text item delimiters to ""
				set replies to 0
				repeat with r in recentIn
					if (all headers of r) contains mid then set replies to replies + 1
				end repeat
				set end of out to mid & " due=" & dueEpoch & " isDue=" & (dueEpoch ≤ nowEpoch) & " replies=" & replies
			end if
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	return out as text
end run
