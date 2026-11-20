#!/bin/sh
# Builds .build/app/FlyByMail.app (host app + Mail extension), universal, by hand like the other menu-bar apps.
#
# Usage: scripts/build.sh [identity]
#   identity — codesign identity substring, e.g. "Developer ID" (hardened runtime, timestamped); omit to sign ad-hoc.
#   SPARKLE=1 (env) — distribution build: embed Sparkle and write its update keys (scripts/make-dmg.sh sets it).
#   FEED_REPO (env) — GitHub repo that serves appcast.xml and the DMG releases (default Marcus1571/flyby-mail).
# Install: rm -rf /Applications/FlyByMail.app && ditto .build/app/FlyByMail.app /Applications/FlyByMail.app
set -eu
cd "$(cd "$(dirname "$0")/.." && pwd)"

IDENTITY="${1:-}"
VERSION="${VERSION:-$(grep -m1 -oE '^## [0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md | sed 's/^## //')}"
# Numeric build Sparkle compares (CFBundleVersion and the appcast): 0.1.0 -> 100
BUILD="$(echo "$VERSION" | awk -F. '{print $1*10000+$2*100+$3}')"
SPARKLE="${SPARKLE:-0}"
FEED_REPO="${FEED_REPO:-Marcus1571/flyby-mail}"
APP=".build/app/FlyByMail.app"
EXT="$APP/Contents/PlugIns/FlyByMailExtension.appex"
MIN="13.0"

rm -rf .build/app .build/obj && mkdir -p "$APP/Contents/MacOS" "$EXT/Contents/MacOS" "$APP/Contents/Resources" .build/obj
./scripts/make-icon.sh
SPARKLE_FLAGS=""
if [ "$SPARKLE" = 1 ]; then ./scripts/fetch-sparkle.sh && SPARKLE_FLAGS="-F .build/sparkle -framework Sparkle -D SPARKLE"; fi

for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -module-name FlyByMail -target "$arch-apple-macos$MIN" \
    $SPARKLE_FLAGS Sources/FlyByMail/*.swift -o ".build/obj/FlyByMail-$arch"
  # _NSExtensionMain is the entry point of every app extension; the principal class comes from Info.plist.
  swiftc -O -parse-as-library -module-name FlyByMailExtension -target "$arch-apple-macos$MIN" \
    -framework MailKit -framework AppKit \
    Sources/FlyByMailExtension/*.swift -Xlinker -e -Xlinker _NSExtensionMain \
    -o ".build/obj/FlyByMailExtension-$arch"
done
lipo -create .build/obj/FlyByMail-arm64 .build/obj/FlyByMail-x86_64 -output "$APP/Contents/MacOS/FlyByMail"
lipo -create .build/obj/FlyByMailExtension-arm64 .build/obj/FlyByMailExtension-x86_64 -output "$EXT/Contents/MacOS/FlyByMailExtension"

mkdir -p "$APP/Contents/Resources/engine" && cp Resources/engine/*.applescript "$APP/Contents/Resources/engine/" && cp Resources/FlyByTemplate*.png Resources/paypal-qr.png "$APP/Contents/Resources/"
mkdir -p "$EXT/Contents/Resources" && cp Resources/FlyByTemplate*.png "$EXT/Contents/Resources/"
cp .build/AppIcon.icns "$APP/Contents/Resources/"
sed "s/__VERSION__/$VERSION/;s/__BUILD__/$BUILD/" Resources/app-Info.plist > "$APP/Contents/Info.plist"
if [ "$SPARKLE" = 1 ]; then
  # Sparkle is a dynamic framework next to the executable; it carries its XPC services and the Autoupdate helper. The public key is the
  # operator's shared key pair (private half in the login keychain, never in a repo).
  mkdir -p "$APP/Contents/Frameworks" && cp -R .build/sparkle/Sparkle.framework "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/FlyByMail"
  P=/usr/libexec/PlistBuddy; I="$APP/Contents/Info.plist"
  $P -c "Add :SUFeedURL string https://raw.githubusercontent.com/$FEED_REPO/main/appcast.xml" "$I"
  $P -c "Add :SUPublicEDKey string 4X6j0DXdJCmcxqe3fkMKWxKuuHhhM+rYrK5LauHe9UA=" "$I"
  $P -c "Add :SUEnableAutomaticChecks bool true" "$I"
  $P -c "Add :SUScheduledCheckInterval integer 86400" "$I"
fi
sed "s/__VERSION__/$VERSION/;s/__BUILD__/$BUILD/" Resources/ext-Info.plist > "$EXT/Contents/Info.plist"

# Sign deepest-first: the extension (sandboxed, as every app extension must be), then the app that carries it.
if [ -n "$IDENTITY" ]; then
  [ "$SPARKLE" = 1 ] && codesign --force --options runtime --timestamp --deep --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --entitlements Resources/ext.entitlements --sign "$IDENTITY" "$EXT"
  codesign --force --options runtime --timestamp --entitlements Resources/app.entitlements --sign "$IDENTITY" "$APP"
else
  [ "$SPARKLE" = 1 ] && codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --entitlements Resources/ext.entitlements --sign - "$EXT"
  codesign --force --entitlements Resources/app.entitlements --sign - "$APP"
fi
codesign --verify --deep --strict "$APP" && echo "Built $APP (version $VERSION, signed: ${IDENTITY:-ad-hoc})"
