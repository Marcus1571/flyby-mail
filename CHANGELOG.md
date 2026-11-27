# Changelog

## 0.3.2

**Fix: reminder mails no longer pile up in Sent.** Found by the operator on 2026-11-27: every "FlyBy: nobody replied to …" reminder appeared in the Yahoo Sent folder next to the
mails really sent. A reminder is a mail from the account to itself, so Mail kept a Sent copy like for any other mail; the engine also used that copy to avoid sending a reminder twice.

- `Resources/engine/common.applescript` (behaviour): new `trashMailboxOf(acct)`, the account's Trash ("Trash", "Deleted Messages", "Deleted Items", "Bin", "Cestino", "Posta eliminata"). Gmail
  accounts (server name contains gmail/googlemail) answer none: Gmail's Sent and Inbox copies of a mail to yourself are one message, so trashing it would also take the reminder out of the inbox.
- `Resources/engine/remind.applescript` (behaviour): after sending, the reminder's id is read from its Sent copy as before, then the copy is moved to Trash (`toTrash`). The "already sent"
  check looks in Sent and Trash, so the duplicate guard from 0.2.2 still works while Trash keeps the copy (a reminder found there is reused). A reminder reused from Sent is moved too.
  The messages are dereferenced (`contents of`) before moving: a loop variable is only a pointer into the list and `move` failed silently on it (seen while cleaning up, see findings).
- Cleanup done by hand the same day on the operator's Mac: the 28 older reminder copies in Sent (27 Yahoo, 1 iCloud) moved to Trash; the inbox copies stay.

## 0.3.1

**Fix: a sent reminder's claim no longer expires.** Found in the first live test on 2026-11-23: the Mac that lost the claim kept the mail pending, the claim freed itself after 10 minutes,
the loser then won it and only its Sent check (which depends on IMAP sync) stopped a second reminder. Now the winner tells the service it sent, and the other Macs drop the mail.

- `backend/server.py` (behaviour): new column `done` (added automatically to a 0.3.0 database). `POST /claim {"id", "done": true}` marks the caller's own claim done (another device's claim is left alone);
  a done claim is never won again, by anyone, and every answer now carries `"done"`. Log event `done`. Same path as `/claim`, so the relay Worker needs no change.
- `backend/test_server.py`: done claim never expires and only the holder can finish; a 0.3.0 database gets the column; HTTP round trip with `done`.
- `Sources/FlyByMail/Engine.swift` (behaviour): `Backend.Result.done(holder)`; after a successful send that won the claim, `Backend.finish` reports it (failure is logged as `finish-failed` and falls back to the
  10-minute expiry). A claim answered `done` by another Mac clears the entry (status `cleared`, log `claim-done`): that Mac marks and unmarks its reminder. Body built as a typed dictionary (the ternary crashed the compiler).
- `scripts/check-engine.sh`: the winner finishes, the second Mac now gets `done` from the holder.
- Compatibility: a 0.3.0 Mac reads a done claim as "lost" and keeps the mail pending without sending (harmless, retries every tick) until it updates.

## 0.3.0

New: **optional claim service** so two Macs on one mailbox never both send the same reminder. Found 2026-11-23: with the engine on two Macs, both sent the reminder for one mail 34 s apart,
because the first Mac's reminder had not yet synced over IMAP into the second Mac's Sent folder, so the 0.2.2 "look in Sent" check could not see it. Only a server both ask at the same instant can decide.
Without the service nothing changes (the engine works as in 0.2.2).

- `backend/` (new, a separate container, not part of the app bundle): `server.py` (stdlib Python + SQLite; `POST /claim` with a per-Mac bearer key, one atomic upsert decides the winner, a claim frees itself after 10 min,
  only SHA-256(Message-Id) + device label + time are stored, rows deleted after 60 days, JSON log line per claim), `Dockerfile`, `compose.yaml` (127.0.0.1 only, read-only, no capabilities), `.env.example`,
  `test_server.py` (20 simultaneous claims give one winner; same device again wins; TTL expiry; auth and validation over HTTP), `README.md` (setup).
- `Sources/FlyByMail/Engine.swift` (behaviour, only when configured): `Backend.claim` before sending a reminder. Won: send. Lost: stay pending, log `claim-lost` (the next tick finds the winner's reminder in Sent and reuses it).
  Service unreachable: wait, log `claim-unavailable`; an entry more than 30 min late is sent anyway so a dead server cannot silence reminders. Config: defaults key `backendURL`; the Mac's key and the optional Cloudflare Access
  service token (sent as `CF-Access-Client-Id` / `CF-Access-Client-Secret`) live in the Keychain. Nothing is built into the app.
- `scripts/check-engine.sh`: also starts `backend/server.py` and runs the real client against it (first Mac wins, second loses and sees the holder, unreachable service is "unavailable").

## 0.2.2

**Fix: a new machine no longer replays old reminders.** On 2026-11-23 the operator installed FlyByMail on a second Mac (Macai) with the same Yahoo account. Its state.json was empty, the
Sent folder still held tagged test mails from 19-22 Nov already handled on the first Mac, and the engine returned 10 of them as reminder mails to the operator's own inbox, up to 4 days late
(`late_by_s` 340080). There was no lateness limit, no first-run baseline and no per-tick cap, and the duplicate check only looked 6 hours back.

- `Sources/FlyByMail/Engine.swift` (behaviour): a tagged mail seen for the first time more than `graceSeconds` (10 min, for a Mac that slept through a tick) after its due time is **not** tracked: log
  event `expired` with `late_by_s`, no entry, no reminder (`isExpiredOnFirstSight`). Mails the engine saw before they were due still come back late as before.
- `Engine.swift` (behaviour): at most `maxReturnsPerTick` (3) reminders are sent per tick, oldest due first; the rest stay pending for the next tick, log event `cap-reached` and a macOS
  notification (`notify`). Second belt in case the first rule is ever bypassed.
- `Resources/engine/remind.applescript` (behaviour): the "already sent" check now looks in Sent for a reminder with the same subject whose body contains this mail's Message-Id link, of **any age**
  (was: same subject within 6 hours). The mailbox is shared by every machine on the account, so a second Mac finds the first Mac's reminder and reuses it instead of sending another.
- `scripts/check-engine.sh` (new, no behaviour): builds `Engine.swift` with a tiny main and asserts the expiry rule (4 days late, 601 s late, 599 s, due now, future), the cap and `parseTag`.

## 0.2.1

Opening the "Remind me about the selected mail" panel again on a mail that already has a reminder now shows where it stands (found in the operator's test of 0.2.0: the panel came up empty).

- `Sources/FlyByMail/ReminderPanel.swift` and `Engine.swift` (behaviour): `entry(for:)` finds the reminder of the selected mail (by its own Message-Id or by its reminder mail's). Pending: the green "Reminder set, comes back …"
  card with a "Cancel reminder" link (`cancel()`, log event `cancelled`); returned, answered or dismissed: an orange note says so ("The reminder came back, returned 00:04") and a new time can be picked.
- `Sources/Shared/Picker.swift`: `PanelNote`, the confirmation card shows it; times for today are written `HH:mm` like the other dates (they read "0:37" before); the panel title is "Bring this back".

## 0.2.0

New: **remind me about any mail or conversation**, not only mails you send. Mail has no toolbar API, so it opens from the menu-bar item "Remind me about the selected
mail…" or the global shortcut ⌃⌘R: select a mail in Mail, pick a time (the same ten presets and a date and time), and if nobody replies after that moment it comes back
as a reminder mail like the others, quoting the mail ("From:", "Received:").

- `Sources/Shared/Picker.swift` (new): the picker moved here from the extension so both targets share it (`scripts/build.sh` compiles it into the app and the extension).
- `Sources/Shared/Picker.swift` (behaviour): the "Only if nobody replies" switch is **gone** from the picker; every reminder is "if nobody replies" (operator's decision, a laconic
  reply is handled by reminding on the conversation afterwards). The header stays `noreply=1`; the older "switch off" paths in the engine are now unused but harmless.
- `Sources/FlyByMail/ReminderPanel.swift` (new): the panel (confirms with the mail's subject and sender, closes itself after the pick), the "select a mail first" notice, the
  ⌃⌘R hot key (Carbon, needs no permission). `App.swift`: the menu item and the hot key.
- `Sources/FlyByMail/Engine.swift`: `Entry.source` ("received"), `selectedMail()`, `track()`; the reminder call passes the source; a picked mail that was deleted is dropped and logged
  (`original-missing`) instead of retried forever.
- `Resources/engine/selected-mail.applescript` (new) reads the selected mail; `remind.applescript` finds a picked mail in the account's mailboxes and writes the From/Received lines.

## 0.1.7

- `Resources/engine/remind.applescript` and `Sources/FlyByMail/Engine.swift` (behaviour): a mail sent with "only if nobody replies" OFF now comes back as
  "FlyBy: reminder for “…”" with the line "This is the reminder you asked for. It comes back whether or not someone replied." Before, every reminder said
  "FlyBy: nobody replied to …" and "Nobody has replied to this mail yet", which was false when you had answered (Off test 5, 2026-11-22). The engine passes the
  switch to the script as a third argument; mails sent with the switch ON are unchanged.

## 0.1.6

- `Sources/FlyByMail/Engine.swift` (behaviour): the engine now waits **an hour** (by the clock) for a returned reminder to show up in Mail before it stops trying to mark
  it. It counted ticks (12), but the 30 s quick retry makes 12 ticks only about 6 minutes; in the operator's Off test 5 Mail exposed the reminder to scripting
  about 3.5 minutes after Yahoo delivered it, and it was marked on the 10th try.
- `Resources/engine/notjunk-selection.applescript` (behaviour): the menu item "Mark selected mail as Not Junk" failed with "Can't make item 1 of selection into type
  specifier" (error -1700); it now reads the selection into a variable first, like the other selection action.

## 0.1.5

- `Resources/engine/activity.applescript` and `Sources/FlyByMail/Engine.swift` (behaviour): the check "did anyone answer a returned mail" now takes one cut-off per
  mail (arguments `<messageId>|<ageSeconds>`) and only counts mail that arrived **after that reminder came back**. Before, one shared window reached back to the
  previous check, so a reply that landed *before* the return (switch off, answered ahead of time) cleared the marks of the freshly returned reminder one minute
  later ("a reply arrived", `unmarked 0`). Found in the operator's Off test 3, 2026-11-22; Off test 2 hit the sibling cause fixed in 0.1.4.

## 0.1.4

- `Sources/FlyByMail/Engine.swift` (behaviour): taking the marks off a returned mail because "you replied" now needs the reply to be written **after** the reminder came
  back (was: any follow-up since the mail was sent). With "only if nobody replies" off and a follow-up written before the due time, 0.1.3 returned the reminder and
  then immediately dropped its marks, so it arrived in the Inbox unflagged and uncoloured (found in the operator's switch-off test, Off test, 2026-11-22).

## 0.1.3

- `Sources/FlyByMail/Engine.swift` (behaviour): the "you replied to your own mail since sending, so do not return it" rule now applies only to mails sent with
  "only if nobody replies" on. Before, a mail with the switch off was also dropped when you had written a follow-up, so a plain timed reminder could silently
  not come back. Found while planning the switch-off test.

## 0.1.2

- `Sources/FlyByMail/About.swift` (new, behaviour): the About page now matches UsageBar and NeverSleep: icon, version and build, a PayPal support card
  (QR, three tier buttons, link), a Report a Bug card (issues page), a License and code card, one-line tagline. It was a plain text stub.
- `Sources/FlyByMail/App.swift`: `AboutView` moved out; hidden `--snapshot-about <dir>` writes light and dark PNGs of the page (used to check the look).
- `Resources/paypal-qr.png` (new, same asset as UsageBar) and `scripts/build.sh` (copies it into the app).

## 0.1.1

- `Sources/FlyByMailExtension/Extension.swift` (behaviour): the picker's "Done" button is gone. Mail owns the popover and has no API to close it
  from inside, so the button never closed it and its close attempts beeped. The green confirmation now says "All set. Click anywhere outside
  to close." The `closePicker` code was removed.
- `README.md`: install, behaviour, backend plan, build.

## 0.1.0

First distributable build: notarized DMG, Sparkle updates, app icon, About window. Behaviour is the tested engine plus extension
(see STATUS.md); nothing else changed in how mails are tracked, returned or marked.

- `scripts/build.sh`: version now comes from this file's top heading (was hard-coded 0.0.1); `SPARKLE=1` embeds Sparkle 2.10.1, links
  the host app against it and writes the update keys into Info.plist; the app icon is generated from `Resources/icon/AppIcon.svg`.
- `scripts/fetch-sparkle.sh`, `make-icon.sh`, `make-dmg.sh`, `make-appcast.sh`: new, copied from the sibling apps' pipeline.
- `Sources/FlyByMail/App.swift`: menu items "Check for Updates…" and "About FlyBy…"; About window.
- `Resources/app-Info.plist`: icon, copyright.
