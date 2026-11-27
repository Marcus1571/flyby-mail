#!/bin/zsh
# Regenerates appcast.xml for the given version from a built, signed DMG.
#
# Usage: scripts/make-appcast.sh <version> [dmg]
#   dmg defaults to build/dist/FlyByMail-<version>.dmg (from make-dmg.sh).
#
# The enclosure URL points at the GitHub Release asset, which the release flow
# must have published by the time the appcast commit is pushed (push order:
# tag + GitHub Release first, then `git push origin main`).
#
# The EdDSA signature uses Sparkle's private key stored in this machine's login
# keychain (sign_update); the matching public key is baked into the app's
# Info.plist (SUPublicEDKey), so only DMGs signed with that key pass.
set -euo pipefail
cd "${0:A:h:h}"

VERSION="${1:?Usage: make-appcast.sh <version> [dmg]}"
FEED_REPO="${FEED_REPO:-Marcus1571/flyby-mail}"
DMG="${2:-build/dist/FlyByMail-${VERSION}.dmg}"
FEED_URL="https://raw.githubusercontent.com/${FEED_REPO}/main/appcast.xml"
APPCAST="appcast.xml"

[ -f "$DMG" ] || { echo "DMG missing: $DMG (run make-dmg.sh first)" >&2; exit 1; }
[ -x .build/sparkle/bin/sign_update ] || ./scripts/fetch-sparkle.sh
SIGN_TOOL=".build/sparkle/bin/sign_update"

DMG_LENGTH="$(stat -f %z "$DMG")"
SIGN_LINE="$("$SIGN_TOOL" "$DMG")"
SIGNATURE="$(echo "$SIGN_LINE" | sed -n 's/^sparkle:edSignature="\([^"]*\)".*/\1/p')"
SIGNED_LENGTH="$(echo "$SIGN_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
if [ -z "$SIGNATURE" ] || [ -z "$SIGNED_LENGTH" ] || [ "$SIGNED_LENGTH" != "$DMG_LENGTH" ]; then
  echo "sign_update output not understood: $SIGN_LINE" >&2
  exit 1
fi
PUB_DATE="$(LC_ALL=en_US.UTF-8 date -u +"%a, %d %b %Y %H:%M:%S GMT")"
ENCLOSURE_URL="https://github.com/${FEED_REPO}/releases/download/v${VERSION}/FlyByMail-${VERSION}.dmg"
NUMERIC_VERSION="$(echo "$VERSION" | awk -F. '{print $1*10000+$2*100+$3}')"

cat > "$APPCAST" <<EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>FlyByMail</title>
    <link>${FEED_URL}</link>
    <description>Most recent FlyByMail releases.</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:releaseNotesLink>https://github.com/${FEED_REPO}/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
      <enclosure url="${ENCLOSURE_URL}"
                 sparkle:version="${NUMERIC_VERSION}"
                 sparkle:shortVersionString="${VERSION}"
                 sparkle:edSignature="${SIGNATURE}"
                 length="${DMG_LENGTH}"
                 type="application/octet-stream" />
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
EOF

echo "Wrote $APPCAST (version ${VERSION}, build ${NUMERIC_VERSION})"
echo "$SIGN_LINE"
