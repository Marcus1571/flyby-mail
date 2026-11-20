# AGENTS.md — FlyBy for Mail

> **Read first, every session:** load `GOVERNANCE.md` and `USER.md` from the operator's private `governance`
> GitHub repo (see `GOVERNANCE.md` → "The two fixed, universal files"). This file wins when the two disagree
> on a FlyBy-for-Mail-specific fact; cross-cutting principles still apply.

## What this project is

The Apple Mail side of **FlyBy** (see the sibling `flyby` repo): a notarized Mac app that carries a **Mail extension**,
so that someone who uses Apple Mail (a non-technical user) gets the Gmail-panel experience: pick a time and
"if nobody replies" in a button in Mail's Compose window, nothing else to learn. Distribution: Developer ID + notarized DMG
on GitHub (no App Store), like the operator's other menu-bar apps.

## Decision: where the engine lives (operator, 2026-11-19)

The engine runs **on the user's Mac, inside the menu-bar app**, through Mail's own scripting (no password, nothing on LT or the VPS).
Until the extension is very mature it stays there. A VPS/IMAP engine (needs the user's app password, runs 24/7, Yahoo/AOL only) is a
later option if a sleeping Mac turns out to matter. Do not build engine parts on LT or the VPS without the operator asking.

## Decision: optional backend, repo public (operator, 2026-11-20; design only, nothing built)

- The app, extension and the Mac engine work **fully on their own**; the repo and the notarized DMG are public (Sparkle feed from this repo).
- An **optional backend** (a container, code in a folder of this repo, self-hostable by anyone; "as is, no support") adds what a Mac cannot:
  reminders while the Mac sleeps, mailboxes via app passwords. The app has a checkbox "Enable backend", an address and an API key, typed by
  the user into the settings (key in the Keychain). **No backend address or key is ever built into the app or the repo.**
- Backend has two doors. **Admin web UI** (login; create/revoke per-device keys, add mailboxes with app passwords, status, a "setup code" to
  paste into the app): behind Cloudflare Access (email gate) or Tailscale Serve (HTTPS). **API door** for the app: own hostname, Cloudflare
  Access service token (two headers) **plus** the backend's own bearer key (random, hashed at rest, per device, revocable); HTTPS only.
  A self-hoster without Cloudflare relies on the key alone. Keep the public API small and its dependencies patched.
- Order: finish testing the Mac side and the DMG first; backend when the operator says the Mac side is ready.

## Conventions

- Built like the other menu-bar apps: hand-assembled bundles from `scripts/build.sh` (no Xcode project), signed with the
  operator's Developer ID (pass `"Developer ID"` as identity, never put team id or personal data in the repo).
- Bundle ids: `app.legba.flybymail` (host), `app.legba.flybymail.extension` (Mail extension).
- Log with `os.Logger`, subsystem `app.legba.flybymail` (`log stream --predicate 'subsystem == "app.legba.flybymail"'`).
- No real hostnames/IPs/emails in repo files.
