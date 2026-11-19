# findings — FlyBy for Mail

Append-only log. Newest first.

## 2026-11-19 — Mail ignores an extension that does not declare its capabilities

- Symptom: `pluginkit -m -p com.apple.email.extension` listed the signed extension (even elected with `+`), but Mail ▸ Settings ▸
  Extensions said "No Extensions".
- Cause: the Info.plist had no `NSExtension ▸ NSExtensionAttributes ▸ MEExtensionCapabilities` array. Xcode's Mail Extension template
  (`Mail Extension.xctemplate/TemplateInfo.plist` in Xcode.app) puts `MEComposeSessionHandler` (and the other chosen handlers) there;
  `MEComposeSession` (icon = SF Symbol name, tooltip) sits in the same `NSExtensionAttributes`.
- Lesson: pluginkit registration is not proof that Mail lists the extension; check Mail's Extensions pane.

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
