#!/bin/zsh
# Distribution DMG: build/dist/FlyByMail-<version>.dmg, Developer ID signed, notarized and stapled.
# Usage: scripts/make-dmg.sh   (identity and notary profile are the operator's, from the login keychain)
set -euo pipefail
cd "${0:A:h:h}"
NOTARY_PROFILE="diskledplus-notary"
IDENTITY="Developer ID Application"
VERSION="${VERSION:-$(grep -m1 -oE '^## [0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md | sed 's/^## //')}"
DMG="build/dist/FlyByMail-${VERSION}.dmg"
STAGING="build/dmg-staging"

VERSION="$VERSION" SPARKLE=1 ./scripts/build.sh "$IDENTITY"

rm -rf "$STAGING"; mkdir -p "$STAGING" build/dist
ditto .build/app/FlyByMail.app "$STAGING/FlyByMail.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "FlyByMail" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

set +e
OUT="$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"; STATUS=$?
set -e
if [ $STATUS -eq 0 ] && echo "$OUT" | grep -q "status: Accepted"; then
  xcrun stapler staple "$DMG" && xcrun stapler validate "$DMG"
  echo "Notarized + stapled: $DMG"
else
  echo "Notarization did not succeed:"; echo "$OUT"; exit 1
fi
