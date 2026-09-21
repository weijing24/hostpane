# Sourced by package-app.sh and with-clt-stubs.sh.
# Command Line Tools has no Metal compiler. From CLT 27 / Swift 6.4, SwiftPM
# may invoke `xcrun metal` or `xcodebuild -downloadComponent MetalToolchain`.
# Stubs satisfy the build graph; Hostpane does not ship the metallib.
#
# Do not set DEVELOPER_DIR to a fake tree: xcrun then looks for a real
# Xcode.app and `swift` fails.

hostpane_setup_clt_metal_stubs() {
  root="$1"
  stub_dir="$root/.build/hostpane-tool-stubs"
  mkdir -p "$stub_dir"

  if ! hostpane_real_metal_ok "$stub_dir"; then
    hostpane_write_metal_stub "$stub_dir/metal"
    cp "$stub_dir/metal" "$stub_dir/metallib"
    cp "$stub_dir/metal" "$stub_dir/metal-ar"
    chmod +x "$stub_dir/metal" "$stub_dir/metallib" "$stub_dir/metal-ar"

    hostpane_write_xcrun_wrapper "$stub_dir" "$stub_dir/xcrun"
    hostpane_write_xcodebuild_wrapper "$stub_dir/xcodebuild"
    chmod +x "$stub_dir/xcrun" "$stub_dir/xcodebuild"
  fi

  sdk26="$(hostpane_macos26_sdk)"
  if [ -n "$sdk26" ] && hostpane_needs_macos26_sdk; then
    hostpane_write_swift_wrapper "$stub_dir/swift" "$sdk26"
    chmod +x "$stub_dir/swift"
    export SDKROOT="$sdk26"
  fi

  # PATH catches `metal`, `xcrun metal`, and a `swift` wrapper that pins
  # the macOS 26 SDK when CLT 27's default SDK lacks SwiftUIMacros.
  export PATH="$stub_dir:$PATH"
}

hostpane_macos26_sdk() {
  if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ]; then
    echo /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
    return 0
  fi
  ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1
}

hostpane_needs_macos26_sdk() {
  # SDK 27 turns @State into SwiftUIMacros.StateMacro; that plugin is not
  # in Command Line Tools (it ships with full Xcode). xcrun --show-sdk-path
  # stays MacOSX.sdk (a symlink), so version is the reliable check.
  dev="$(/usr/bin/xcode-select -p 2>/dev/null)" || return 1
  case "$dev" in
    *CommandLineTools*) ;;
    *) return 1 ;;
  esac
  ver="$(/usr/bin/xcrun --show-sdk-version 2>/dev/null)" || return 1
  major="${ver%%.*}"
  [ "$major" -ge 27 ] 2>/dev/null
}

hostpane_write_swift_wrapper() {
  dest="$1"
  sdk="$2"
  cat > "$dest" <<EOF
#!/bin/sh
real=/usr/bin/swift
sdk="$sdk"
case "\$1" in
  build|run|test)
    sub="\$1"
    shift
    exec "\$real" "\$sub" --build-system native --sdk "\$sdk" "\$@"
    ;;
  *)
    exec "\$real" "\$@"
    ;;
esac
EOF
}

hostpane_real_metal_ok() {
  stub_dir="$1"
  found=""
  found="$(PATH=/usr/bin:/bin /usr/bin/xcrun --find metal 2>/dev/null)" || true
  if [ -z "$found" ] || [ ! -x "$found" ]; then
    return 1
  fi
  case "$found" in
    "$stub_dir"/*)
      return 1
      ;;
  esac
  out="$("$found" --version 2>&1)" || true
  case "$out" in
    *[Rr]equires\ Xcode*|*[Mm]etal\ [Tt]oolchain*|Hostpane\ metal\ stub*)
      return 1
      ;;
  esac
  return 0
}

hostpane_write_metal_stub() {
  cat > "$1" <<'EOF'
#!/bin/sh
# Satisfies SwiftPM's Metal compile graph without Xcode's metal toolchain.
for arg in "$@"; do
  case "$arg" in
    --version|-v)
      echo "Hostpane metal stub"
      exit 0
      ;;
    --help|-help|-h)
      echo "Hostpane metal stub"
      exit 0
      ;;
  esac
done
write_empty() {
  if [ -n "$1" ]; then
    mkdir -p "$(dirname "$1")"
    : > "$1"
  fi
}
name="$(basename "$0")"
if [ "$name" = metal-ar ]; then
  for arg in "$@"; do
    case "$arg" in
      -*|r|d|q|x|t|s|c|u) ;;
      *) write_empty "$arg" ;;
    esac
  done
  exit 0
fi
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
  case "$arg" in
    -o*)
      if [ "$arg" != "-o" ]; then
        out="${arg#-o}"
      fi
      ;;
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
}

hostpane_write_xcrun_wrapper() {
  stub_dir="$1"
  dest="$2"
  cat > "$dest" <<EOF
#!/bin/sh
# Intercept metal / metallib / metal-ar, including \`xcrun --find metal\`.
stub_dir="$stub_dir"
real=/usr/bin/xcrun
find_mode=0
tool=""
for arg in "\$@"; do
  case "\$arg" in
    -find|--find|-f) find_mode=1 ;;
    metal|metallib|metal-ar) tool="\$arg" ;;
  esac
done
if [ -n "\$tool" ]; then
  if [ "\$find_mode" = 1 ]; then
    echo "\$stub_dir/\$tool"
    exit 0
  fi
  while [ \$# -gt 0 ]; do
    case "\$1" in
      -find|--find|-f)
        shift
        ;;
      -sdk|--sdk|--toolchain|-toolchain|--add-toolchain)
        shift
        [ \$# -gt 0 ] && shift
        ;;
      metal|metallib|metal-ar)
        shift
        exec "\$stub_dir/\$tool" "\$@"
        ;;
      *)
        shift
        ;;
    esac
  done
  exec "\$stub_dir/\$tool"
fi
exec "\$real" "\$@"
EOF
}

hostpane_write_xcodebuild_wrapper() {
  dest="$1"
  cat > "$dest" <<'EOF'
#!/bin/sh
# CLT 27 may tell SwiftPM to `xcodebuild -downloadComponent MetalToolchain`.
# Hostpane only needs the compile graph to succeed.
for arg in "$@"; do
  case "$arg" in
    MetalToolchain|metalToolchain)
      exit 0
      ;;
  esac
done
exec /usr/bin/xcodebuild "$@"
EOF
}
