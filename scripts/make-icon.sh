#!/bin/zsh
# Resources/icon/AppIcon.svg -> .build/AppIcon.icns (needs rsvg-convert: brew install librsvg). Generated at build time, never committed.
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build && rm -rf .build/AppIcon.iconset && mkdir .build/AppIcon.iconset
for s in 16 32 128 256 512; do
  rsvg-convert -w $s -h $s Resources/icon/AppIcon.svg -o .build/AppIcon.iconset/icon_${s}x${s}.png
  rsvg-convert -w $((s*2)) -h $((s*2)) Resources/icon/AppIcon.svg -o .build/AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns && rm -rf .build/AppIcon.iconset
