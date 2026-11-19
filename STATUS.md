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

## Tests

1. **PASSED 2026-11-19**: extension loads, button + picker work, header `X-Flyby: v=1; due=<epoch>; noreply=1` is on the Yahoo Sent copy. Icon still to confirm visually.
2. Mail scripting: **partly passed 2026-11-19**: scan of tagged Sent mail + reply check + copy of the sent mail into the Yahoo INBOX as unread work (`scripts/spike-*.applescript`). Still to do: move a received message to a FlyBy folder and back; confirm the copy reaches Yahoo's server/iPhone; a real engine loop (nothing runs on its own yet).

## Notarization

Not done yet; the spike only needs a local Developer ID signature. Notarize with the shared `notarytool` profile of the other apps
before giving the DMG to anybody.
