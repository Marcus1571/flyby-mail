# STATUS — FlyBy for Mail

_Last updated: 2026-11-27_

## Where things stand

- **History restarted 2026-11-27** (operator: "clean everything"): the GitHub repo was deleted and recreated with one commit
  and one release (v0.3.1, same DMG at the same URL, so Sparkle updates keep working). The full history (61 commits) and
  releases v0.1.0–v0.3.0 are in the private repo `flyby-mail-archive`. Every other clone (e.g. the second Mac) must be
  deleted and cloned again, not pulled. Open: the About window links to a PayPal address with the operator's real name;
  changing it needs a new notarized build.

- **Spike 1 built (2026-11-19)**: host app + Mail extension (compose button with a time picker and "only if nobody replies",
  stamps an `X-FlyBy: v=1; due=<epoch>; noreply=<0|1>` header on the outgoing message). Builds universal (arm64 + x86_64),
  signed with Developer ID + hardened runtime + app sandbox. Installed in `/Applications`; macOS lists it
  (`pluginkit -m -p com.apple.email.extension`) and it is enabled (`pluginkit -e use`).
- Mail first showed "No Extensions" (Info.plist lacked `MEExtensionCapabilities`, see findings); fixed. Button, picker and header in the Sent copy verified live since (latest: 2026-11-24 two-Mac test).

## Engine built 2026-11-19 (menu-bar app, runs every 5 min)

- `Sources/FlyByMail/Engine.swift` + `Resources/engine/*.applescript` (run through `osascript`, no password; needs the one-time macOS "control Mail" permission).
  Tick: (1) `sent-ids` lists the last 30 days of sent mail (bulk, ~0.4 s), `headers` reads each new one once -> tagged mail becomes a pending entry, and the
  `In-Reply-To` of every sent mail is remembered (what the user replied to); (2) due + pending: if "only if nobody replies", `replies` looks for a real answer
  (not me, not automatic) among newer INBOX mail -> `answered`, else `return` copies the sent mail into INBOX with orange flag + orange background + unread;
  (3) a returned mail the user replied to afterwards gets `unmark` (flag and colour off).
- State: `~/Library/Application Support/FlyByMail/state.json`. Log (JSON lines, why-it-did-what-it-did): `~/Library/Logs/FlyByMail/engine.log`.
- Verified live on the Yahoo test account: tagged -> returned (`copied 1`, idempotent). **Verified live (operator, 2026-11-19 13:38-13:39 local)**: replying to the returned mail and sending it -> the next check logged `unmarked` and the INBOX copy read flagged=false, color=none; the reply sits in the same Mail conversation ("2 Messages"). Ticks ran on schedule every 5 min. Answered-by-recipient verified live 2026-11-24 ("Done test 3", findings 2026-11-24): reply from another address before due -> both Macs logged `answered`, no reminder.
- Menu bar: status, Check now, Open at login, Show log, Welcome, Quit. Host app is `LSUIElement`, entitlement `com.apple.security.automation.apple-events`.

## Bugs found by the operator's multi-account test (2026-11-19, fixed)

- Mail Test 05/06 were sent from Yahoo to the operator's Gmail; the operator replied in Gmail (Gmail treats the Yahoo address as the operator's own, so a Gmail
  "Reply" goes Gmail -> Gmail: test method, not a bug). Mail holds the Google account too, so the replies landed in the **Google** inbox. The engine only searched the
  sending account's inbox, missed the replies (14:58/14:59), and returned both mails at 14:59:47/14:59:51, orange. Fixed: `replies` and the new `activity`
  script search the inboxes of ALL accounts (`every message of inbox`); step 3 of the tick now unmarks a returned mail when you replied in Mail OR any reply to it
  reached any inbox (state `lastActivityScan` limits each look to mail that arrived since the previous one). Verified: both copies unmarked ("a reply arrived").
- No Bcc anywhere: all recent sent mails have bcc=0; neither extension nor engine ever adds one.
- Flag lost after return on 05/06/"Mail test 2" (colour stuck, flag icon missing): Mail applies flag changes with a delay and a synced copy can lose them;
  `return` now marks, waits, reads back and only finishes after the marks held on two checks 3 s apart; result is logged (`copied 1 flagged=true color=orange`). Not yet seen live.
- AppleScript note: reading `flagged status` right after setting it can lag; also `before` is a reserved word.

## Return = a reminder mail to yourself (2026-11-19 22:3x, operator chose option A)

- Found with Test 08/09: a returned **copy** keeps its original date (Test 08: sent 15:31, returned 15:42, still dated 15:31; Mail sorts by date received and `date received` cannot be set),
  so it sits at its old position in the inbox, buried after a day or a week. A mail sent to oneself (Test 09, iCloud -> iCloud) is already in the inbox when due: its "return" is invisible.
- Now `remind.applescript` sends a **new mail from the account to its own address**: subject `FlyBy: nobody replied to "<subject>"`, body = who it went to, when, a `message://` link to the original
  (opens it in Mail) and the quoted original (3000 chars). It arrives dated now: top of the inbox, push notification on the phone. Idempotent (a reminder with that subject and the original's id in Sent or Trash is reused). Since 0.3.2 its Sent copy moves to Trash once its id is read, so Sent holds only real mail (Gmail excepted: one message there).
- Mail delivers mail you send to yourself as read, so `ensure-marks` flags it orange, colours it and sets it unread; the tick polls for the arrival (6 rounds, 10 s apart) and keeps trying on later ticks
  (`marksPending`, up to 12 ticks, log `marks-gave-up`). Entry fields: `markId` (reminder Message-Id), `marksPending`, `marksTries`; older entries (no `markId`) still mark the copy of the original.
  Unmark / dismiss / menu clear / reply detection all act on `markKey` (= reminder id, else original id); replies are still matched against the original id.
- **Verified live end to end on a real Yahoo mail (Test 10, 22:42:52 due)**: reminder sent 22:43:11 (on time), Yahoo delivered it 22:45:10 (~2 min, much slower than iCloud's seconds),
  the next tick marked it 22:47:56: `read=false flagged=true color=orange`. To close the 2-3 min gap the app now re-checks 30 s after any tick that leaves a reminder waiting for its marks.
- Verified live for the script and the marking on Test 09's reminder (arrived 22:36:06, `read=false flagged=true color=orange`). Full engine path (due -> remind -> mark) pending on the next tagged mail.

## Replies judged as junk (2026-11-19, found with Test 07 and Test 10)

- Short replies (e.g. "YELLOOOO") from another of the operator's addresses to the Yahoo address were judged junk: Test 07's reply sat in Yahoo's server-side **Bulk** folder (server filter), and Mail's own
  filter also marked both replies junk (`junk mail status = true`, shown in brown even in the Inbox; no visible "Not Junk" button in the message view once they are in the Inbox).
- `set junk mail status of <msg> to false` works and counts as training: `defaults read com.apple.mail NumberOfMessagesMarkedAsNotJunk` went 2 -> 4.
- Mail's own help: Settings > Junk Mail > exceptions (Contacts, Previous Recipients, VIPs). Yahoo's filter is separate: "Not spam" in Yahoo Mail on the web.
- **Built (2026-11-19, operator: "sure")**: every tick, step 1b runs `rescue.applescript` over the global junk mailbox (Yahoo Bulk, Gmail Spam, iCloud Junk): a real reply to a pending (no-reply) or returned mail gets its junk status cleared, is moved to the Inbox of its own account, and counts as an answer (log event `rescued`). Menu item "Mark selected mail as Not Junk" (`notjunk-selection.applescript`) is the manual fallback. Verified by moving "Re: Mail Test 10" into Yahoo Bulk and running the script: it came back to the Inbox, junk false. Mail has no main-toolbar API, so a Yahoo-style icon is impossible (compose icon only). Not yet seen end to end with a real provider-filed reply. Mail's own filter is off on the operator's Mac; the brown came from the server flag.
- Note: the engine's reply check only looks at inboxes, so an answer that sits in Junk does not cancel a reminder; and the "you replied" rule (your own reply from any account) is what unmarked Test 10's reminder at 23:28.

## Dismissing a returned mail (2026-11-19, operator request)

- Mail's main toolbar cannot get an extension icon (no toolbar API in MailKit; the headers mention none; the only forum thread has no reply). The existing **flag button is the dismiss**:
  click the flag off -> on the next check (or "Check now") the engine removes the orange background and marks the entry cleared (`check-dismissed` script; log reason "you cleared the flag";
  a mail that left the INBOX is cleared too, reason "the mail left the Inbox"). Verified live on "Mail test 2" (flag switched off by script, same effect as the click).
- The 15-minute flag re-check was narrowed: `ensure-marks` now only covers the mails returned in the same tick (after a 12 s settle), otherwise it would put back a flag the user just removed.
- Menu-bar app: "Clear marks on selected mail" (only mails FlyBy returned, via `unmark-selection`) and "Clear marks on all returned mails (N)". Built, not yet clicked by the operator.
- Mail row colours are local to the Mac (Apple Mail does not sync them); the flag syncs. To check on an iPhone.
- Manual clear without FlyBy: select the mail, Format > Show Colors, pick white (per Apple Community answers, not tried).

## Engine never starts Mail by itself (2026-11-19, found while listing what is left to test)

- AppleScript launches any app it addresses, so a tick with Mail closed would have reopened Mail every 5 minutes. Now: Mail closed and nothing due -> tick skipped
  (`tick-skipped` in the log); something due -> Mail is started hidden in the background (`open -g -j -a Mail`, log `starting-mail`). Not yet tested with Mail closed.

## Second round of operator tests (Test 07/08, 2026-11-19 15:30)

- Replies to a mail you sent to yourself can go astray in tests: Gmail (Send-as) and Apple Mail both answer the *original recipient* when the mail is "from you".
  Use a recipient that is not one of your own addresses, or reply and edit the To.
- Test 07: the operator's reply (sent from iCloud to Yahoo at 15:34, before the due time) landed in **Yahoo's Bulk (spam)** folder, so no inbox ever saw it, and the engine returned the mail.
  Spam is deliberately not counted as an answer (nobody would see it). But the reply was the operator's own follow-up in the thread: **new rule (built)**:
  any reply of yours (from any account in Mail) since you sent the mail means it is handled: it is not returned, or loses its marks if already returned (`state.replyTargets` vs `sentAt`).
  Verified: Test 07 unmarked, reason "you replied".
- Test 08 (unanswered) was returned with colour but **no flag**, although `return` had read back `flagged=true`. Likely cause: two returns in one tick; Mail refreshes the inbox after the second copy and the first copy
  comes back without the flag. Built: `ensure-marks` script; the tick waits 12 s after returning, re-checks the marks of mails returned in this tick and in the last 15 minutes (log `marks-checked`).
  Test 08 re-flagged by hand. Not yet seen live.
- Open from before: does Done close the picker (extensionContext attempt), does the app receive the extension's `app.legba.flybymail.pick` message (`ext-pick` in engine.log).
  Info-level system log lines age out within about an hour: watch live with `/usr/bin/log stream` while testing.

## Picker v2 + feedback (2026-11-19)

- Picker v2 (SwiftUI): the Gmail presets with their real times, date and time, only-if-nobody-replies switch. Operator test: works, but setting a time "feels fragile"
  (only a tiny grey line confirmed it). Fix (built, awaiting the operator's look): a framed confirmation panel (grey "No reminder yet" -> green "Reminder set /
  Comes back <time> / if nobody replies"), a Done button that reads "Choose a time" (disabled) until a time is set and then "Done" (closes the picker), a haptic tick on
  every change, and an experiment: while a reminder is set the recipient tokens in the compose window get a green MailKit "success" annotation ("FlyBy: comes back ...")
  so the reminder stays visible after the picker closes (`session.reload()` redraws it). Unknown until seen: whether Mail shows the annotation text, and whether
  `dismiss` / `performClose` really closes the popover.
- Operator test 14:43: picker confirmed lovable. Bugs: (1) the leftover "Test: in 2 minutes" link under the panel looked like the setting: removed;
  (2) Done beeped and did not close: `performClose` on Mail's popover window beeps. Replaced by `closePicker()`, which tries responder-chain NSPopover, delegate,
  presenting VC dismiss, `dismiss`, an Escape key event, `cancelOperation` in turn and logs `close: ... -> closed=<bool>`; result pending.
- In the compose window the recipient token showed a black check mark while a reminder was set (the MailKit success annotation); the tooltip text is unconfirmed.
- Not in the picker yet (engine cannot act on them): follow-up text, private note.

## Operator feedback 2026-11-19 (requirements)

- The returned mail must be unmistakable: "this is NOT a normal incoming mail, it is your mail brought back because nobody answered". Done so far by script:
  orange flag + orange background + unread on the copy (verified by readback). Ideas to push further: extension-side marking (message action handler),
  and an own-authored reminder instead of a plain copy (to be checked: not possible by script alone).
- Test copy arrived with its subject but showed "This message has no content": to check with a mail that has a body.
- The compose picker must grow into the richness of the Gmail pop-up (presets, date and time, only-if-no-reply, follow-up text, note, cancel,
  current reminder) with a native Apple look: SwiftUI, system controls, light/dark, keyboard and VoiceOver friendly.
- Icon confirmed: the brand airplane, monochrome, in the Compose toolbar.

## Tests

1. **PASSED 2026-11-19**: extension loads, button + picker work, header `X-Flyby: v=1; due=<epoch>; noreply=1` is on the Yahoo Sent copy. Icon still to confirm visually.
2. Mail scripting: **partly passed 2026-11-19**: scan of tagged Sent mail + reply check + copy of the sent mail into the Yahoo INBOX as unread work (`scripts/spike-*.applescript`). Still to do: move a received message to a FlyBy folder and back; confirm the copy reaches Yahoo's server/iPhone; a real engine loop (nothing runs on its own yet).

## Distribution (2026-11-20, v0.1.0)

- **Built and verified**: `scripts/make-dmg.sh` builds `build/dist/FlyByMail-0.1.0.dmg` (Developer ID, hardened runtime, Sparkle 2.10.1 embedded,
  app icon and About window), notarized by Apple with the shared `diskledplus-notary` profile and stapled; `spctl` says "Notarized Developer ID"
  for both the DMG and the app. The app's Sparkle keys: shared EdDSA public key, daily check, feed
  `https://raw.githubusercontent.com/$FEED_REPO/main/appcast.xml`.
- **Published 2026-11-20**: repo is public; v0.1.1 (notarized DMG, picker without the Done button) was the first release in the Sparkle feed,
  v0.1.2 (About page like the sibling apps), v0.1.3 (switch-off fix), v0.1.4 (marks kept on a reminder returned after an earlier follow-up), v0.1.5 (same for a reply that arrived before the return), v0.1.6 (waits an hour for the reminder to show up; Not Junk menu item fixed), v0.1.7 (switch-off reminders no longer say "nobody replied"), v0.2.0 (reminders on any selected mail with ⌃⌘R / menu item; the switch is gone), v0.2.1 (the panel shows an existing reminder's status, with Cancel), v0.2.2 (flood protection: mails first seen after their due time are never returned, 3 reminders per tick at most, duplicate check across machines) was followed by 0.3.0 (optional claim service, see backend/README.md; live on the VPS since 2026-11-23 behind Cloudflare Tunnel + Access, reached through a `workers.dev` relay) and 0.3.1 (a sent reminder's claim is marked done, the other Macs drop the mail), the current one (`appcast.xml` on `main` lists only the newest). v0.1.0 is on the Releases page, not in the feed. Optional-backend design: AGENTS.md.
- **Verified 2026-11-20**: Sparkle update 0.1.1 -> 0.1.2 on the operator's Mac (installed app reports 0.1.2, the engine restarted and ticked, macOS lists
  the 0.1.2 extension). Gotcha: an app marked quarantined by hand (not by Finder) runs translocated and Sparkle refuses to update it; remove the
  attribute (`xattr -dr com.apple.quarantine`). Test installs should copy via Finder.
- **iPhone test PASSED 2026-11-22 (operator's screenshots plus engine log)**: "New test 01" (Mac, due 16:40) -> reminder reached the iPhone Yahoo inbox at 16:41
  as the top row, unread, flagged, with the original body quoted; lock-screen banner within about 2 minutes (the original mail's banner also appeared). The operator
  replied "Ok" from the iPhone at 16:46; the reply synced to the Mac and the 16:48 tick logged `unmarked ... "you replied"`, leaving flagged=false, color none.
  Row colour is Mac-only, as expected. Noted: the banner/Lock-screen preview shows the technical header block ("To:/Sent:/Subject:/message://...") instead of
  anything friendly; candidate fix: short human line first, quote next, link last.
- **Switch-off test 2026-11-22**: picker wording confirmed ("Comes back 18:36 even if someone replies"). 0.1.3 returned the mail despite the follow-up, but the
  reminder lost its marks at once (the "you replied" check counted the pre-due follow-up); fixed in 0.1.4. Off test 3 then showed a third cause (the activity scan counted a reply that landed before the return as an answer); fixed in 0.1.5. Off test 5 (switch off, reply before due) then passed: returned, marked orange/flag (Mail exposed the reminder to scripting ~3.5 min after Yahoo delivered it, marked on the 10th retry, which exposed the 6-minute give-up fixed in 0.1.6).
- **Decided 2026-11-22**: the "Only if nobody replies" switch is removed (always on); a laconic reply is handled by reminding on the conversation afterwards: v0.2.0 adds the selected-mail picker (menu item and ⌃⌘R). Tested: picker rendering, `selected-mail` and the received-mail reminder script on the real mailbox; operator test 2026-11-22/23: set from the menu item on Off test 5, the reminder came back at 00:04 (flagged, orange, quoting the mail); reopening the panel was empty, fixed in 0.2.1.
- **Not yet tested**: clean install on a second Mac via Finder drag (first launch, Mail extension enabling, Automation prompt), whether Mail keeps
  the extension ticked after an update, the Mac-asleep case.
- **Incident 2026-11-23**: installing on a second Mac (same Yahoo account, empty state.json) replayed about 10 old reminders into the operator's own inbox; fixed in v0.2.2 (details: `findings.md`, `CHANGELOG.md`). Open: the operator removes the 10 stray `FlyBy:` mails by hand; the second Mac's engine stays off until it runs 0.2.2; central state on the VPS is a later option, not started.
- **2026-11-23, double reminder**: both Macs sent the reminder for one mail 34 s apart (IMAP sync lag hides the first reminder). 0.3.0 adds the claim service; until it is deployed and configured on both Macs, a mail due close to both engines' ticks can still be reminded twice.
- **Claim service live 2026-11-23**: both Macs (labels `sapmac`, `macai`) use it; `ben` and `marcomac` are planned (key made on that Mac, only its SHA-256 goes into the server's `.env`). First live test (mail due 19:52 CET): `sapmac` won and sent, `macai` got `claim-lost` at 20:03, won the expired claim at 20:07 and reused the same reminder from Sent: one reminder, no duplicate. Open gap: a claim expires after 10 min even after a successful send, so the loser retries and only the Sent check prevents a duplicate; fixed in 0.3.1 (the winner marks the claim done after sending, the loser drops the entry: log `claim-done`). 0.3.1 deployed 2026-11-23 21:02 CET: server rebuilt on the VPS (column `done` migrated), live round trip through the relay (claim, done, then `done: true` to the next claim), app installed on both Macs. Verified 2026-11-24 with a real mail: `sapmac` sent and marked done, `macai` logged `claim-done`, one reminder; Always Allow survived the update. After installing or updating the app, quit and reopen Mail (findings 2026-11-24).
