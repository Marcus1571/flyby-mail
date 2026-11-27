-- For the given sent messages, print: <messageId>\t<X-Flyby>\t<In-Reply-To>   (empty fields when absent)
-- argv: account, then message ids (without angle brackets)
on run argv
	set acctName to item 1 of argv
	set outLines to {}
	tell application "Mail"
		set acct to first account whose name is acctName
		set sentBox to my sentMailboxOf(acct)
		repeat with k from 2 to count of argv
			set wanted to item k of argv
			try
				set m to first message of sentBox whose message id is wanted
				set h to all headers of m
				set end of outLines to wanted & tab & (my headerValue(h, "X-Flyby:")) & tab & (my headerValue(h, "In-Reply-To:"))
			on error errText
				set end of outLines to wanted & tab & "ERROR " & errText & tab
			end try
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	return outLines as text
end run
