# STATUS — FlyBy for Mail

_Last updated: 2026-11-19_

## Where things stand

- **Spike 1 built (2026-11-19)**: host app + Mail extension (compose button with a time picker and "only if nobody replies",
  stamps an `X-FlyBy: v=1; due=<epoch>; noreply=<0|1>` header on the outgoing message). Builds universal (arm64 + x86_64),
  signed with Developer ID + hardened runtime + app sandbox. Installed in `/Applications`; macOS lists it
  (`pluginkit -m -p com.apple.email.extension`) and it is enabled (`pluginkit -e use`).
- **Mail first showed "No Extensions"**: the Info.plist lacked `MEExtensionCapabilities` (see findings); fixed, awaiting the re-check in Mail.
- **Not yet verified in Mail**: the button appears, the picker works, the header reaches the sent message and the Sent copy.
- Apple Mail on the operator's Mac has only iCloud and Google accounts; the Yahoo test account still has to be added.

## Engine built 2026-11-19 (menu-bar app, runs every 5 min)

- `Sources/FlyByMail/Engine.swift` + `Resources/engine/*.applescript` (run through `osascript`, no password; needs the one-time macOS "control Mail" permission).
  Tick: (1) `sent-ids` lists the last 30 days of sent mail (bulk, ~0.4 s), `headers` reads each new one once -> tagged mail becomes a pending entry, and the
  `In-Reply-To` of every sent mail is remembered (what the user replied to); (2) due + pending: if "only if nobody replies", `replies` looks for a real answer
  (not me, not automatic) among newer INBOX mail -> `answered`, else `return` copies the sent mail into INBOX with orange flag + orange background + unread;
  (3) a returned mail the user replied to afterwards gets `unmark` (flag and colour off).
- State: `~/Library/Application Support/FlyByMail/state.json`. Log (JSON lines, why-it-did-what-it-did): `~/Library/Logs/FlyByMail/engine.log`.
- Verified live on the Yahoo test account: tagged -> returned (`copied 1`, idempotent). **Verified live (operator, 2026-11-19 13:38-13:39 local)**: replying to the returned mail and sending it -> the next check logged `unmarked` and the INBOX copy read flagged=false, color=none; the reply sits in the same Mail conversation ("2 Messages"). Ticks ran on schedule every 5 min. Not yet verified live: answered-by-recipient path.
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

## Notarization

Not done yet; the spike only needs a local Developer ID signature. Notarize with the shared `notarytool` profile of the other apps
before giving the DMG to anybody.
