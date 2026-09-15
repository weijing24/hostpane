#!/bin/sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

png="$root/Sources/Hostpane/Resources/AppIcon-1024.png"
icns="$root/Sources/Hostpane/Resources/AppIcon.icns"
iconset="$root/Sources/Hostpane/Resources/AppIcon.iconset"

swift "$root/scripts/render-icon.swift" "$png"
rm -rf "$iconset"
mkdir -p "$iconset"
sips -z 16 16     "$png" --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32     "$png" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$png" --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64     "$png" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$png" --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256   "$png" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$png" --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512   "$png" --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$png" --out "$iconset/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$png" --out "$iconset/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$iconset" -o "$icns"
rm -rf "$iconset"
echo "Wrote $icns"
