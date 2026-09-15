#!/bin/sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

"$root/scripts/package-app.sh"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/Sources/Hostpane/Resources/Info.plist")"
arch="$(uname -m)"
app="/Applications/Hostpane.app"
stage="$root/dist/dmg-stage"
dmg="$root/dist/Hostpane-${version}-${arch}.dmg"

rm -rf "$stage" "$dmg"
mkdir -p "$stage"
cp -R "$app" "$stage/Hostpane.app"
ln -s /Applications "$stage/Applications"

cat > "$stage/Install.txt" <<'EOF'
Hostpane
========

Requires macOS 14 or later. This build is Apple Silicon (arm64) only.

1. Drag Hostpane into Applications.
2. First launch: right-click Hostpane.app and choose Open
   (the app is ad-hoc signed, not notarized).
   Or run: xattr -cr /Applications/Hostpane.app

Host book and Keychain items stay on this Mac. Import Host aliases
from ~/.ssh/config after install if you want the same machines.

License: AGPL-3.0 (Traversio).
EOF

hdiutil create \
  -volname "Hostpane" \
  -srcfolder "$stage" \
  -ov \
  -format UDZO \
  "$dmg" >/dev/null

rm -rf "$stage"

echo "Built $dmg"

dropbox="$HOME/Dropbox"
if [ -d "$dropbox" ]; then
  cp -f "$dmg" "$dropbox/$(basename "$dmg")"
  echo "Copied $dropbox/$(basename "$dmg")"
fi
