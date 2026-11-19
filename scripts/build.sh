#!/bin/sh
# Builds .build/app/FlyByMail.app (host app + Mail extension), universal, by hand like the other menu-bar apps.
#
# Usage: scripts/build.sh [identity]
#   identity — codesign identity substring, e.g. "Developer ID" (hardened runtime, timestamped); omit to sign ad-hoc.
# Install: rm -rf /Applications/FlyByMail.app && ditto .build/app/FlyByMail.app /Applications/FlyByMail.app
set -eu
cd "$(cd "$(dirname "$0")/.." && pwd)"

IDENTITY="${1:-}"
VERSION="0.0.1"
BUILD="1"
APP=".build/app/FlyByMail.app"
EXT="$APP/Contents/PlugIns/FlyByMailExtension.appex"
MIN="13.0"

rm -rf .build/app .build/obj && mkdir -p "$APP/Contents/MacOS" "$EXT/Contents/MacOS" .build/obj

for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -module-name FlyByMail -target "$arch-apple-macos$MIN" \
    Sources/FlyByMail/*.swift -o ".build/obj/FlyByMail-$arch"
  # _NSExtensionMain is the entry point of every app extension; the principal class comes from Info.plist.
  swiftc -O -parse-as-library -module-name FlyByMailExtension -target "$arch-apple-macos$MIN" \
    -framework MailKit -framework AppKit \
    Sources/FlyByMailExtension/*.swift -Xlinker -e -Xlinker _NSExtensionMain \
    -o ".build/obj/FlyByMailExtension-$arch"
done
lipo -create .build/obj/FlyByMail-arm64 .build/obj/FlyByMail-x86_64 -output "$APP/Contents/MacOS/FlyByMail"
lipo -create .build/obj/FlyByMailExtension-arm64 .build/obj/FlyByMailExtension-x86_64 -output "$EXT/Contents/MacOS/FlyByMailExtension"

sed "s/__VERSION__/$VERSION/;s/__BUILD__/$BUILD/" Resources/app-Info.plist > "$APP/Contents/Info.plist"
sed "s/__VERSION__/$VERSION/;s/__BUILD__/$BUILD/" Resources/ext-Info.plist > "$EXT/Contents/Info.plist"

# Sign deepest-first: the extension (sandboxed, as every app extension must be), then the app that carries it.
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --timestamp --entitlements Resources/ext.entitlements --sign "$IDENTITY" "$EXT"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  codesign --force --entitlements Resources/ext.entitlements --sign - "$EXT"
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP" && echo "Built $APP (version $VERSION, signed: ${IDENTITY:-ad-hoc})"
