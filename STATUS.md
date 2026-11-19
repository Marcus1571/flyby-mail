# STATUS — FlyBy for Mail

_Last updated: 2026-11-19_

## Where things stand

- **Spike 1 built (2026-11-19)**: host app + Mail extension (compose button with a time picker and "only if nobody replies",
  stamps an `X-FlyBy: v=1; due=<epoch>; noreply=<0|1>` header on the outgoing message). Builds universal (arm64 + x86_64),
  signed with Developer ID + hardened runtime + app sandbox. Installed in `/Applications`; macOS lists it
  (`pluginkit -m -p com.apple.email.extension`) and it is enabled (`pluginkit -e use`).
- **Not yet verified in Mail**: the button appears, the picker works, the header reaches the sent message and the Sent copy.
- Apple Mail on the operator's Mac has only iCloud and Google accounts; the Yahoo test account still has to be added.

## Tests

1. Extension loads and stamps the header (Gmail account first, Yahoo after it is added).
2. Mail scripting moves a message out of the inbox and back, and can read headers (reply check). Not started.

## Notarization

Not done yet; the spike only needs a local Developer ID signature. Notarize with the shared `notarytool` profile of the other apps
before giving the DMG to anybody.
