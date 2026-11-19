# AGENTS.md — FlyBy for Mail

> **Read first, every session:** load `GOVERNANCE.md` and `USER.md` from the operator's private `governance`
> GitHub repo (see `GOVERNANCE.md` → "The two fixed, universal files"). This file wins when the two disagree
> on a FlyBy-for-Mail-specific fact; cross-cutting principles still apply.

## What this project is

The Apple Mail side of **FlyBy** (see the sibling `flyby` repo): a notarized Mac app that carries a **Mail extension**,
so that someone who uses Apple Mail (Ben, a non-technical user) gets the Gmail-panel experience: pick a time and
"if nobody replies" in a button in Mail's Compose window, nothing else to learn. Distribution: Developer ID + notarized DMG
on GitHub (no App Store), like the operator's other menu-bar apps.

## Conventions

- Built like the other menu-bar apps: hand-assembled bundles from `scripts/build.sh` (no Xcode project), signed with the
  operator's Developer ID (pass `"Developer ID"` as identity, never put team id or personal data in the repo).
- Bundle ids: `app.legba.flybymail` (host), `app.legba.flybymail.extension` (Mail extension).
- Log with `os.Logger`, subsystem `app.legba.flybymail` (`log stream --predicate 'subsystem == "app.legba.flybymail"'`).
- No real hostnames/IPs/emails in repo files.
