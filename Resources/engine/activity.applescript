-- Did anyone answer any of these returned mails? Looks once at the messages that reached ANY account's inbox recently and prints the ids
-- (one per line) that some message replies to (In-Reply-To / References), counting only mail that arrived AFTER that mail's own cut-off.
-- Used to take the marks off returned mails that have been answered, whoever answered and wherever the answer landed.
-- argv: one item per returned mail, "<messageId>|<ageSeconds>" (no angle brackets); only messages newer than ageSeconds count for that id.
on run argv
	set nowDate to current date
	set wantList to {}
	set ageList to {}
	set maxAge to 0
	set AppleScript's text item delimiters to "|"
	repeat with a in argv
		set parts to text items of (contents of a)
		set end of wantList to item 1 of parts
		set oneAge to (item 2 of parts) as integer
		set end of ageList to oneAge
		if oneAge > maxAge then set maxAge to oneAge
	end repeat
	set AppleScript's text item delimiters to ""
	set matched to {}
	tell application "Mail"
		set newer to (every message of inbox whose date received > (nowDate - maxAge))
		repeat with m in newer
			set h to all headers of m
			set refs to (my headerValue(h, "In-Reply-To:")) & " " & (my headerValue(h, "References:"))
			set msgAge to nowDate - (date received of m)
			repeat with k from 1 to count of wantList
				set wanted to item k of wantList
				if refs contains wanted and msgAge < (item k of ageList) and matched does not contain wanted then set end of matched to wanted
			end repeat
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	return matched as text
end run
