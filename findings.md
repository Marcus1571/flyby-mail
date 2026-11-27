# findings — FlyBy for Mail

Append-only log. Newest first.

## 2026-11-27 — reminder copies in Sent; moving mail from AppleScript loops

- The operator saw every reminder in the Yahoo Sent folder. Expected from the design: a reminder is a mail to yourself, Mail keeps its Sent copy, and the engine used that copy as its
  duplicate guard. Fix (0.3.2): move the copy to Trash after reading its id, look in Sent and Trash for duplicates. Not on Gmail: one message carries the Inbox and Sent labels there.
- Tested live: one Yahoo reminder moved Sent -> Trash, its inbox copy untouched (`sent=0 trash=1 inbox=1`).
- Two AppleScript traps while moving 27 at once: (1) `repeat with m in (every message … whose …)` re-runs the query on every step, so after a few moves "Invalid index" (-1719);
  first `set hits to (every message …)`, then loop. (2) `m` is a reference to a list item; passing it to `move` inside a `try` failed silently. Use `contents of m`.

## 2026-11-26 (research: can the extension show a FlyBy band above a message?)

- Asked because a reply like "Ok" ends the wait silently and Mail shows no FlyBy state on the message. Mail has no DOM to inject into
  (unlike Gmail web, where the Chrome extension can add a bar above the thread) and legacy `.mailbundle` plug-ins are off on current macOS.
- One official hook exists, read from the macOS 27.2 SDK headers: `MEMessageDecoder.decodedMessage(forMessageData:)` (part of
  `MEMessageSecurityHandler`) may return an `MEDecodedMessage` with a `banner` (`MEDecodedMessageBanner`: title, one action button,
  dismissable). Header text: "a suggestion banner at the top of the message view"; the button opens the extension's view controller
  (`primaryActionClicked(forMessageContext:)`), which could offer "keep waiting" / "done".
- Limits: text plus one button, colour chosen by Mail (no custom band); the API is meant for S/MIME/PGP, so FlyBy would return the
  original bytes unchanged with empty security information; the extension would need `MEMessageSecurityHandler` in
  `MEExtensionCapabilities` and the user to enable it again in Mail ▸ Settings ▸ Extensions; it needs the reminder list from the app
  (shared container) to match `In-Reply-To`/`References`.
- Unknown, to verify with a spike: whether Mail calls the decoder for plain, unsigned mail at all (the header says "if the extension is
  not needed ... return quickly with nil", which suggests every message), and whether Mail caches the result so the banner goes stale.
- Verdict: worth a spike; fallback is the row colour and flag FlyBy already sets (list only, not inside the message).

## 2026-11-19 — Mail ignores an extension that does not declare its capabilities

- Symptom: `pluginkit -m -p com.apple.email.extension` listed the signed extension (even elected with `+`), but Mail ▸ Settings ▸
  Extensions said "No Extensions".
- Cause: the Info.plist had no `NSExtension ▸ NSExtensionAttributes ▸ MEExtensionCapabilities` array. Xcode's Mail Extension template
  (`Mail Extension.xctemplate/TemplateInfo.plist` in Xcode.app) puts `MEComposeSessionHandler` (and the other chosen handlers) there;
  `MEComposeSession` (icon = SF Symbol name, tooltip) sits in the same `NSExtensionAttributes`.
- Lesson: pluginkit registration is not proof that Mail lists the extension; check Mail's Extensions pane.

## 2026-11-19 (research: can the compose toolbar icon change, and can Done close the picker?)

- Compose icon/tooltip come from `Info.plist` (`MEComposeSession` ▸ `MEComposeIcon`, `MEComposeIconToolTip`). WWDC21 "Build Mail app extensions", its notes, the Medium
  article and the MailKit headers show no API to change icon, badge or state at runtime (Thunderbird's `composeAction` can; MailKit cannot). The only Apple
  Developer Forums thread on toolbar icons (699500, main-viewer toolbar) has 0 replies. No open-source MailKit extension found with a dynamic icon; `triage`
  (follow-up from compose) uses `osascript`, a CGEvent tap and macOS notifications, and shows nothing in the compose window.
- Per-recipient annotation works (`MEAddressAnnotation.success`, `session.reload()`): the token gets a black check mark; our text shows at the top of the token's menu.
- Known MailKit bugs (macOS 12.4 era, may be fixed): `allowMessageSendForSession` never called (FB10533807), `rawData` nil (FB10533893).
- **The picker runs out of process**: responder chain `PickerViewController > NSView > MEExtensionServiceViewController > NSWindow`, window delegate nil. Closing Mail's
  popover from inside failed with every method tried (presentingViewController.dismiss, dismiss, Escape key event, cancelOperation; `performClose` on the window beeps).
  Still to try: `extensionContext.completeRequest`. Fallback: no closing button; green "Reminder set" panel, click outside to close.
- Ideas for visible feedback outside the toolbar (all need the extension to tell the menu-bar app what was picked, being tested via a distributed notification `app.legba.flybymail.pick`):
  a floating status pill attached to the compose window, a menu-bar title, a macOS notification after send.

## 2026-11-19 (engine gotchas)

- `osascript` output is trimmed: a line ending in an empty tab-separated field loses its tab; pad fields when parsing.
- AppleScript prints big numbers locale-formatted (`1,795089226E+9`): print small integers (ages in seconds) and compute epochs in Swift.
- Bulk property fetch only works as `message id of (every message of box whose ...)`; through a variable holding the list it fails. Reserved/unusable
  variable names found: `lines`, `dates`, `ids`, `inBox` (any case of `inbox`), `st`, `copies`.
- macOS `sed` has no `\b`: use perl for word-boundary renames.

## 2026-11-19 (marking a returned mail)

- Operator: a returned mail needs a clear "this is your mail reproposed, nobody answered" look. Mail has no labels; by script
  `set flag index of <msg> to 1` (orange flag) + `set background color of <msg> to orange` + `set read status ... to false` all worked on the Yahoo INBOX copy
  (read back: flagged=true, flagIndex=1, color=orange, read=false). Flags and colours sync to other Apple devices as IMAP keywords; other mail clients may ignore them.
- MailKit's message action handler can also flag/colour messages as they download (docs), but it may not fire for a copy created locally by script: to test.

## 2026-11-19 (test 2, partly) — Mail scripting can find tagged mail, check replies and copy a sent mail into the inbox

- The tag alone does nothing: the first test mail (due in 2 min) "never came back" because no engine existed. The picker's "Returns ..." text
  promises something only an engine can do.
- `scripts/spike-scan.applescript` (read only): lists the Sent mails carrying `X-Flyby`, their due epoch and whether a reply is in the
  last 7 days of the inbox (reply = inbox mail whose headers contain the sent Message-Id). Worked on the Yahoo account.
- `scripts/spike-return.applescript`: `duplicate <sent message> to <INBOX>` created exactly one copy in the Yahoo INBOX; `set read status ... to false`
  made it unread. Find messages with `whose message id contains "<id>"`.
- AppleScript gotchas hit: Mail's `inbox` property is case-insensitive, so a variable named `inBox` breaks (`Can't set inbox of application`);
  `st`, `copies` are unusable names; `duplicate` must be a plain statement, its result cannot be assigned.
- Not yet checked: that the copy exists on Yahoo's server (iPhone / Yahoo web), moving a *received* thread out of the inbox and back, and
  whether Apple Mail shows the copy inside the same conversation.

## 2026-11-19 (test 1 PASSED) — header stamped and present on the Yahoo Sent copy

- From the Yahoo account in Apple Mail, with the picker set to "In 2 minutes (test)": the extension log shows
  `headers: X-FlyBy: v=1; due=<epoch>; noreply=1` at send (due = send + 2 min), and the **Sent copy in the Yahoo account's Sent folder carries
  `X-Flyby: v=1; due=...; noreply=1`** (Mail normalizes the name's case). So a later engine can find tagged mails by reading Sent.
- Mail's AppleScript works from Terminal without a new permission prompt: `all headers of message` on a Yahoo Sent message returned the header
  (read only the X-FlyBy/Message-Id/Date lines; never print other headers or bodies in logs).
- Not found in Gmail: the test mail's recipient was an auto-completed contact, probably not the Gmail address; irrelevant for the result.

## 2026-11-19 — Mail extension must be ticked inside Mail; compose icon

- `pluginkit -e use` ("+") is macOS's own election, **not** the checkbox in Mail ▸ Settings ▸ Extensions. Mail's log said
  `Extension app.legba.flybymail.extension is userEnabled: Not Enabled and optedIn: YES` until the user ticked the box
  (`/usr/bin/log show --predicate 'process == "Mail" AND eventMessage CONTAINS[c] "flyby"'`; in zsh `log` is a builtin, use the full path).
- Once ticked: compose begin, the toolbar button, and the picker popover all worked (operator screenshot). Mail shows the permission text
  "Email Contents: can read sensitive information from emails including the message subject and recipients. This applies to all outgoing messages."
- `MEComposeIcon` = `airplane.departure` (SF Symbol name) was ignored (generic puzzle-piece icon). Replaced by the brand airplane as a template image:
  `scripts/make-compose-icon.swift` renders `Resources/icon/flyby-icon.svg` (copy of the FlyBy brand plane) to `FlyByTemplate.png`/`@2x.png`,
  copied into the appex `Resources`; `MEComposeIcon` = `FlyByTemplate`. Not yet confirmed visually.

## 2026-11-23 — Mass resend on a second Mac (Macai): root cause and fix

- Symptom: installing FlyByMail on Macai (Apple Mail, same Yahoo account as the operator's own Mac) sent about 10 reminder mails for old test mails; `engine.log` shows 16 tagged, 10 `returned`
  (up to 4 days late), 2 `answered`. The reminders go From/To the operator's own address (by design), so none reached third parties. The engine was stopped by hand (kill) within minutes.
- Cause: state.json is local to each Mac and starts empty; IMAP syncs the whole Sent folder, so the old tagged mails looked new and overdue. Nothing limited lateness or volume.
- Fix in v0.2.2 (CHANGELOG): expired-on-first-sight, cap 3 per tick, duplicate check across machines by Message-Id link in the body.
- Not done, discussed: central state on the VPS (SQLite behind a small HTTP endpoint, atomic claim per mail, per-account lease). Worth it only when two machines run the engine continuously;
  SQLite itself cannot be shared over a network mount. Cleanup of the 10 reminders in the operator's Yahoo mailbox is manual.

## 2026-11-23 — Claim service live: Keychain prompt, DNS filter, expiring claim

- A key saved with `security add-generic-password` is readable only by `security`; the app's first `SecItemCopyMatching` opens a Keychain dialog and the engine tick blocks
  until it is answered (Macai: 15 min, tick `ms` 618152). Answer with **Always Allow**. Over SSH the login keychain is locked ("User interaction is not allowed"): create keys in a GUI session.
- A corporate DNS filter on one Mac blocks the whole `.top` TLD (TLS error from the filter's block page). A Cloudflare Worker on `workers.dev` (`backend/relay/worker.js`) forwards only
  `/claim` and `/health`, adds the Access service token itself, and passes the Mac's key through; Macs then need only their own key.
- The key hash on the server must be of the key without a trailing newline (`printf %s`), else `bad key`.
- Live test: winner sent, loser `claim-lost`; 10 min later the claim had expired, the loser won and its Sent check reused the reminder. Works, but relies on IMAP sync; fix planned (claim marked done after sending).

## 2026-11-24 — Two-Mac claim-done verified; updating the app under a running Mail

- Live test "Done test 2" (sent 09:47 CET, due 09:58): `sapmac` claimed at 10:00:43, sent the reminder and marked the claim done at 10:01:04; `macai` asked at 10:02:44, got
  `done: true` and logged `claim-done` ("sent by sapmac, dropped"). One reminder, no Sent check needed. Keychain Always Allow survived the 0.3.1 update on both Macs (no prompt).
- Replacing `/Applications/FlyByMail.app` while Mail runs breaks the compose extension: the FlyBy button does nothing, PlugInKit logs Code=16 ("other version in use").
  Quit and reopen Mail after every install or update (whether a Sparkle update hits the same is not yet seen).
- "Done test 1" (2026-11-23) went out without `X-FlyBy`: Mail asked for headers but the extension had no pick for that session. Cause not reproduced; in test 2 every field edit
  in the date picker registered a pick (`picked choice=custom(...)` in a `log stream --level info` of subsystem `app.legba.flybymail`), and the header arrived. Check: send only after
  the panel shows green "Reminder set". Side effect seen: while typing, the picker briefly registers intermediate dates (once a time already in the past); harmless unless sent mid-edit.

## 2026-11-24 — Answered-by-recipient verified live ("Done test 3")

Sent from Yahoo 10:43:42 local with "only if nobody replies", due 10:55. Tagged by `sapmac` 10:45:40 and `macai` 10:47:43. The recipient (the operator's iCloud address,
replying with Spark on the phone) answered at 10:45. At due time both Macs logged `answered` / `not returned`; no reminder went out, no claim was made.
- `macai` (Mail has only Yahoo): `by` = the iCloud address. It found the incoming reply, so this is the real recipient path.
- `sapmac` (Mail has iCloud, Google, Yahoo): `by: "you"`, `followup_at` 10:44:59. The reply sat in the iCloud Sent mailbox, so the engine's "you followed up
  from any account in Mail" rule matched first (Engine.swift step 2). Correct outcome, but on this Mac the test cannot exercise the recipient path when the
  recipient is one of your own accounts. To test the recipient path itself, use an address that is not in Mail on that Mac.
