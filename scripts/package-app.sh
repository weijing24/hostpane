#!/bin/sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

ci=0
for arg in "$@"; do
  case "$arg" in
    --ci) ci=1 ;;
    *)
      echo "Unknown option: $arg (expected --ci)" >&2
      exit 1
      ;;
  esac
done

# shellcheck disable=SC1091
. "$root/scripts/lib/clt-metal-stubs.sh"
hostpane_setup_clt_metal_stubs "$root"

swift build -c release --product Hostpane
bin_dir="$(swift build -c release --show-bin-path)"
app="$root/dist/Hostpane.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Hostpane" "$app/Contents/MacOS/Hostpane"
cp "$root/Sources/Hostpane/Resources/Info.plist" "$app/Contents/Info.plist"
# New filename so IconServices does not reuse the old teal-server cache entry.
cp "$root/Sources/Hostpane/Resources/AppIcon.icns" "$app/Contents/Resources/Hostpane.icns"
cp "$root/Sources/Hostpane/Resources/AppIcon-1024.png" "$app/Contents/Resources/Hostpane.png"
printf 'APPL????' > "$app/Contents/PkgInfo"
chmod +x "$app/Contents/MacOS/Hostpane"

if [ "$ci" = 1 ]; then
  # GitHub Actions: leave the signed app in dist/ for the DMG step.
  xattr -cr "$app" >/dev/null 2>&1 || true
  codesign --force --sign - "$app"
  echo "Built $app"
  exit 0
fi

# Sign only after the app is in /Applications. Signing dist/Hostpane.app
# registers a path we then delete; Command-Tab keeps that stale icon.

installed="/Applications/Hostpane.app"
osascript -e 'tell application "Hostpane" to quit' >/dev/null 2>&1 || true
killall Hostpane >/dev/null 2>&1 || true
sleep 0.3
rm -rf "$installed"
cp -R "$app" "$installed"
rm -rf "$app"
xattr -cr "$installed" >/dev/null 2>&1 || true
codesign --force --sign - "$installed"
# Do not NSWorkspace.setIcon: it drops a 0-byte Icon\r in the bundle root.
touch "$installed"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$lsregister" ]; then
  "$lsregister" -u "$root/dist/Hostpane.app" >/dev/null 2>&1 || true
  "$lsregister" -u "$root/dist/dmg-stage/Hostpane.app" >/dev/null 2>&1 || true
  "$lsregister" -u /Volumes/Hostpane/Hostpane.app >/dev/null 2>&1 || true
  "$lsregister" -f "$installed" >/dev/null 2>&1 || true
fi
rm -rf "$HOME/Library/Caches/com.apple.iconservices" \
       "$HOME/Library/Caches/com.apple.iconservices.store" 2>/dev/null || true
find "$HOME/Library/Caches" /private/var/folders -maxdepth 5 \( \
    -name 'com.apple.dock.iconcache' -o \
    -name 'com.apple.iconservices' -o \
    -name 'com.apple.iconservicesagent' \
  \) -exec rm -rf {} + 2>/dev/null || true
killall iconservicesagent >/dev/null 2>&1 || true
killall Dock >/dev/null 2>&1 || true

echo "Installed $installed"
