# FlyBy for Mail

Bring a mail back to your Inbox **if nobody replies**: for Apple Mail on the Mac. Write a mail, click the airplane in the compose
toolbar, pick a time (and "only if nobody replies"), send as usual. When the time comes and nobody has answered, a reminder mail
appears at the top of your Inbox, unread, flagged and orange. Answer it, or untick the flag, and the marks go away.

It is the Apple Mail sibling of [FlyBy for Gmail](https://github.com/Marcus1571/flyby), a free re-implementation of the useful part of
Boomerang. No account, no server, no tracking: everything runs on your Mac through Mail's own extension and scripting.

Tested with Yahoo, iCloud and Gmail accounts in Apple Mail, macOS 13 or newer.

## Install

1. Download `FlyByMail-<version>.dmg` from [Releases](https://github.com/Marcus1571/flyby-mail/releases), open it and drag the app to Applications.
   It is signed and notarized by Apple, so it opens normally.
2. Open FlyBy for Mail. An airplane appears in the menu bar; a short welcome explains the rest.
3. In Mail: Settings ▸ Extensions ▸ tick **FlyBy**.
4. macOS asks once whether FlyBy may control Mail. Allow it: that is how FlyBy finds your sent mails and brings them back.

The app updates itself (Sparkle) and can open at login. Quit it and nothing is checked; reminders due meanwhile come back at the next start.

## How it behaves

- The mail you send is stamped with a small `X-FlyBy` header; the menu-bar app reads it from your Sent folder. Nothing leaves your Mac.
- Checks run every 5 minutes while Mail is open. If Mail is closed at the due time, it is started hidden to return the reminder.
- A reply that the provider filed as junk is rescued to the Inbox and counts as an answer.
- Not a Mail feature: Mail has no API for toolbar buttons or labels, so the confirmation lives in the picker and the returned mail is marked orange.

## Optional backend (planned)

Not built yet. The idea: a small self-hosted container for what a Mac cannot do (reminders while the Mac sleeps). The app will have an
"Enable backend" checkbox, an address and an API key that you type in yourself; nothing is ever built in. The code will live in this repo
and is provided as is, without support.

## Build from source

`scripts/build.sh` builds the app and extension (arm64 + x86_64, ad-hoc signed); `scripts/build.sh "Developer ID"` signs for distribution.
`scripts/make-dmg.sh` makes the notarized DMG (needs the author's signing identity and notary profile). Needs the Xcode command line tools
and `librsvg` (`brew install librsvg`) for the icon. Install: `rm -rf /Applications/FlyByMail.app && ditto .build/app/FlyByMail.app /Applications/FlyByMail.app`.

## For contributors and agents

`AGENTS.md` (rules), `STATUS.md` (where things stand), `findings.md` (research log), `CHANGELOG.md`. MIT licensed.
