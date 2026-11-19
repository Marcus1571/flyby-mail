-- Spike test 2, step 2: "return" ONE tagged, due mail: copy it from Sent into INBOX and mark the copy unread.
-- Safety: only a Sent message whose Message-Id matches argv item 2 AND that carries an X-Flyby header is touched.
-- Usage: osascript scripts/spike-return.applescript "Yahoo!" "<message-id>"
on headerValue(allHeaders, wanted)
	repeat with ln in paragraphs of allHeaders
		set t to contents of ln
		if t starts with wanted then return text ((length of wanted) + 1) thru -1 of t
	end repeat
	return ""
end headerValue

on run argv
	set acctName to item 1 of argv
	set wantedId to item 2 of argv
	tell application "Mail"
		set acct to first account whose name is acctName
		set sentFolder to mailbox "Sent" of acct
		set inboxBox to mailbox "INBOX" of acct
		repeat with m in (messages of sentFolder)
			set h to all headers of m
			if (my headerValue(h, "X-Flyby:")) is not "" and (my headerValue(h, "Message-Id:")) contains wantedId then
				duplicate m to inboxBox
				delay 3 -- the copy is made on the server; give Mail a moment to list it
				set found to (messages of inboxBox whose message id contains wantedId)
				repeat with c in found
					set flag index of c to 1 -- orange flag (FlyBy orange): "this is your mail coming back, not a new one"
					set background color of c to orange
					set read status of c to false
				end repeat
				return "copied; matching messages in INBOX now: " & (count of found)
			end if
		end repeat
	end tell
	return "no matching tagged message"
end run
