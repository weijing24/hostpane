#!/bin/sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! command -v metal >/dev/null 2>&1 && ! xcrun --find metal >/dev/null 2>&1; then
  # Command Line Tools has no `metal`. SwiftTerm's .metal resource still needs a
  # compiler during the Swift Build graph; stubs satisfy the graph. The packaged
  # app does not ship that metallib (package copies only Hostpane + icon).
  stub_dir="$root/.build/hostpane-tool-stubs"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/metal" <<'EOF'
#!/bin/sh
write_empty() {
  if [ -n "$1" ]; then
    mkdir -p "$(dirname "$1")"
    : > "$1"
  fi
}
out=""
deps=""
dia=""
prev=""
for arg in "$@"; do
  case "$prev" in
    -o) out="$arg" ;;
    -MF) deps="$arg" ;;
    -serialize-diagnostics) dia="$arg" ;;
  esac
  prev="$arg"
done
write_empty "$out"
write_empty "$dia"
if [ -n "$deps" ]; then
  mkdir -p "$(dirname "$deps")"
  printf '%s: \n' "${out:-Shaders.air}" > "$deps"
fi
exit 0
EOF
  cp "$stub_dir/metal" "$stub_dir/metallib"
  chmod +x "$stub_dir/metal" "$stub_dir/metallib"
  export PATH="$stub_dir:$PATH"
fi

swift build -c release --product Hostpane
bin_dir="$(swift build -c release --show-bin-path)"
app="$root/dist/Hostpane.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Hostpane" "$app/Contents/MacOS/Hostpane"
cp "$root/Sources/Hostpane/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Sources/Hostpane/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$root/Sources/Hostpane/Resources/AppIcon-1024.png" "$app/Contents/Resources/AppIcon.png"
printf 'APPL????' > "$app/Contents/PkgInfo"
chmod +x "$app/Contents/MacOS/Hostpane"
# Do not drop *.bundle in the .app root: codesign then fails with
# "unsealed contents present in the bundle root". The Dock icon is
# Contents/Resources/AppIcon.icns via Bundle.main, not Bundle.module.
codesign --force --sign - "$app"

installed="/Applications/Hostpane.app"
rm -rf "$installed"
cp -R "$app" "$installed"
xattr -cr "$installed" >/dev/null 2>&1 || true
codesign --force --sign - "$installed"
rm -rf "$app"
# Do not NSWorkspace.setIcon: it drops a 0-byte Icon\r in the bundle root.
touch "$installed"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$lsregister" ]; then
  "$lsregister" -f "$installed" >/dev/null 2>&1 || true
fi
rm -rf "$HOME/Library/Caches/com.apple.iconservices" \
       "$HOME/Library/Caches/com.apple.iconservices.store" 2>/dev/null || true
killall Dock >/dev/null 2>&1 || true

echo "Installed $installed"
