-- Lists recently sent messages (bulk property fetch, cheap): one line per message
--   <account>\t<messageId>\t<ageSeconds>
-- argv: daysBack
on run argv
	set daysBack to (item 1 of argv) as integer
	set nowDate to current date
	set outLines to {}
	tell application "Mail"
		repeat with acct in accounts
			set sentBox to my sentMailboxOf(acct)
			if sentBox is not missing value then
				set cutoff to nowDate - daysBack * days
				set idList to (message id of (every message of sentBox whose date sent > cutoff))
				set sentDates to (date sent of (every message of sentBox whose date sent > cutoff))
				if (count of idList) > 0 then
					repeat with i from 1 to count of idList
						set end of outLines to (name of acct) & tab & (item i of idList) & tab & (((nowDate - (item i of sentDates)) as integer) as text)
					end repeat
				end if
			end if
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	return outLines as text
end run
