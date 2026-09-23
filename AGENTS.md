# AGENTS.md

Personal macOS SwiftUI app (SPM, no `.xcodeproj`). Traversio SSH, SwiftTerm
PTY, SFTP. License is AGPL-3.0 because of Traversio.

## Build without full Xcode

Command Line Tools is enough. Do **not** tell the user to install Xcode.app
for a local compile.

```bash
./scripts/with-clt-stubs.sh swift run HostpaneCheck
./scripts/package-app.sh          # release .app → /Applications/Hostpane.app
./scripts/with-clt-stubs.sh swift run Hostpane
```

`scripts/lib/clt-metal-stubs.sh` (sourced by the scripts above) puts stubs
on `PATH`:

- `metal` / `metallib` / `metal-ar` and an `xcrun` wrapper, because SwiftTerm
  `.process("Apple/Metal/Shaders.metal")` needs a Metal compiler in the
  graph. The packaged app does not ship that metallib.
- `xcodebuild -downloadComponent MetalToolchain` is a no-op.
- On CLT 27+, a `swift` wrapper pins **macOS 26 SDK** and
  `--build-system native`. Bare `swift build` against SDK 27 fails with
  `SwiftUIMacros.StateMacro` / `plugin for module 'SwiftUIMacros' not found`
  (`@State` became a macro; the plugin ships with Xcode, not CLT).
  `xcrun --show-sdk-path` stays `MacOSX.sdk` (symlink); use
  `xcrun --show-sdk-version`.

Do **not** set `DEVELOPER_DIR` to a fake Xcode tree. `swift` then looks for
a real `Xcode.app` and dies.

GitHub Actions (`.github/workflows/release-dmg.yml`) selects Xcode on
`macos-26` and does not need the CLT workarounds.

`--build-system native` is deprecated; keep it until SwiftUIMacros is in
CLT or the default `swiftbuild` backend can compile SwiftUI without Xcode.

## Install after compile

A local Hostpane compile is finished only after `/Applications/Hostpane.app`
is replaced. Use `./scripts/package-app.sh` — it release-builds, then
installs and ad-hoc signs there. Do not leave the new binary only in
`.build/` or `/tmp`.

`HostpaneCheck` is not installed.

## Do not

- Recreate an Xcode project.
- Notarize (ad-hoc sign only).
- Commit `.build/`, `dist/`, or `commit.txt`.
