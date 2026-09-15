# Hostpane

Personal macOS app: host book, SSH over [Traversio](https://github.com/GitSwiftHQ/Traversio), Keychain secrets, Linux `/proc` metric cards, and an embedded [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) terminal.

This is not a SwiftServer clone. Traversio is AGPL-3.0, so Hostpane is AGPL-3.0 as well.

## Requirements

- macOS 14+
- Swift 6.2+ command line tools
- GitHub SSH access (`git@github.com`) for package resolve

Full Xcode is not required.

## Run

```bash
cd hostpane
swift run HostpaneCheck
chmod +x scripts/package-app.sh
./scripts/package-app.sh
open /Applications/Hostpane.app
```

Debug without bundling:

```bash
swift run Hostpane
```

## Disk image

```bash
chmod +x scripts/package-dmg.sh
./scripts/package-dmg.sh
```

Installs `/Applications/Hostpane.app`, writes `dist/Hostpane-<version>-<arch>.dmg`, and copies the dmg to `~/Dropbox` when that folder exists. First launch on another Mac: right-click Open, or `xattr -cr /Applications/Hostpane.app`. The binary is ad-hoc signed, not notarized.

If an older copy crashed on launch with `NSBundle.module`, replace it with a build from this script. That crash was a missing resource bundle, not signing.

## Usage

1. Add a host, or import `Host` aliases from `~/.ssh/config` (patterns like `*` are skipped).
2. Connect. Auth tries SSH agent and default keys, or a saved Keychain password / key file.
3. Metric cards sample Linux `/proc` every two seconds. The terminal is a PTY on a dedicated SSH connection. SFTP opens a separate session from the machine card folder button.

Hostnames are stored as you enter them. The app does not invent IPs.

Passwords and key passphrases go in the login Keychain service `eu.jimwei.hostpane`.
