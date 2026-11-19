-- Did anyone answer any of these returned mails? Looks once at the messages that reached ANY account's inbox in the last
-- <sinceAge> seconds and prints the ids (one per line) that some message replies to (In-Reply-To / References).
-- Used to take the marks off returned mails that have been answered, whoever answered and wherever the answer landed.
-- argv: sinceAgeSeconds, then message ids (no angle brackets)
on run argv
	set sinceAge to (item 1 of argv) as integer
	set nowDate to current date
	set matched to {}
	tell application "Mail"
		set newer to (every message of inbox whose date received > (nowDate - sinceAge))
		repeat with m in newer
			set h to all headers of m
			set refs to (my headerValue(h, "In-Reply-To:")) & " " & (my headerValue(h, "References:"))
			repeat with k from 2 to count of argv
				set wanted to item k of argv
				if refs contains wanted and matched does not contain wanted then set end of matched to wanted
			end repeat
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	return matched as text
end run
