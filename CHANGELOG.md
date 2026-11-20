# Changelog

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
