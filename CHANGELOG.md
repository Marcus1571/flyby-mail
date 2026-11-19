# Changelog

## 0.1.0

First distributable build: notarized DMG, Sparkle updates, app icon, About window. Behaviour is the tested engine plus extension
(see STATUS.md); nothing else changed in how mails are tracked, returned or marked.

- `scripts/build.sh`: version now comes from this file's top heading (was hard-coded 0.0.1); `SPARKLE=1` embeds Sparkle 2.10.1, links
  the host app against it and writes the update keys into Info.plist; the app icon is generated from `Resources/icon/AppIcon.svg`.
- `scripts/fetch-sparkle.sh`, `make-icon.sh`, `make-dmg.sh`, `make-appcast.sh`: new, copied from the sibling apps' pipeline.
- `Sources/FlyByMail/App.swift`: menu items "Check for Updates…" and "About FlyBy…"; About window.
- `Resources/app-Info.plist`: icon, copyright.
