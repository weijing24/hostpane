# Hostpane

<p align="center">
  <img src="Sources/Hostpane/Resources/AppIcon-1024.png" width="128" height="128" alt="Hostpane">
</p>

# Monitor, connect, and run your servers.

Live monitoring, a real terminal, and SFTP on the Mac.
Nothing to install on your server.

Hostpane is a personal macOS app in the same shape as [SwiftServer](https://swiftserver.app/): a host book, live status cards, an SSH shell, and file transfer — all over the SSH you already use.

## See everything. Install nothing.

Hostpane reads live metrics over your existing SSH connection with plain, read-only commands.
No agent, no daemon, no leftovers.

These are the cards on every machine's status page; open one to look closer.

| Card | What it shows |
| --- | --- |
| **CPU** | Every core, segment by segment |
| **Load** | The 1, 5, and 15 minute story |
| **Memory** | Used, cached, free, and swap |
| **Processes** | Who is eating the box, sorted |
| **Network** | Live throughput per interface |
| **Storage** | Volumes, plus real disk I/O |
| **Docker** | Running containers on the status page |

Linux first. Synology DSM is recognized from `/etc.defaults/VERSION`. Pick a default network interface or volume when `/` is not the real disk.

The dashboard samples every couple of seconds. Refresh all, or only the cards that failed.

## A real terminal.

A PTY on a dedicated SSH connection, rendered by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).

Connecting is honest about what is happening: network, handshake, authentication, then shell — the same progress card you would see on SwiftServer.

- Pop a session out into its own window; it keeps running after you leave the main pane
- An inspector keeps live CPU, load, processes, and memory next to the session
- Keep-alive is `ServerAliveInterval` in app form, so idle routers do not drop you
- Fonts, cursor shape, bell, and a light/dark palette that follows the app appearance

## Files over SFTP.

A separate SFTP session from the folder button on a machine card.

Browse, upload, download, rename, mkdir, and delete. Double-click text for a built-in preview, or hand it to the system default app. Hidden files and keep-alive are toggles, not extra SSH flags.

## Traversio. The engine underneath.

The same open-source SSH2 engine SwiftServer ships: [Traversio](https://github.com/GitSwiftHQ/Traversio), written in Swift.

Terminal, SFTP, and monitoring all ride it.

- Modern crypto by default: Curve25519, AES-GCM, ChaCha20-Poly1305
- Host keys you can actually read: SHA-256 fingerprint before you trust
- Auth from SSH agent (including 1Password), a key file, or a Keychain password
- Import `Host` aliases from `~/.ssh/config` (patterns like `*` are skipped)

Traversio is AGPL-3.0, so Hostpane is AGPL-3.0 as well. The engine is public on GitHub — anyone can read the code that carries the traffic.

## A real Mac app.

Written in Swift and compiled for macOS. Split view, menus, toolbar search, tags, and batch edit — not an iPad layout stretched to fill a desktop.

Hostnames are stored as you enter them. The app does not invent IPs.

## None of your data is anyone else's business.

Hostpane has no servers of its own. This Mac talks straight to yours.

- No account to create
- Passwords and key passphrases stay in the login Keychain service `eu.jimwei.hostpane`
- The host book, settings, and key list can live in iCloud Drive or Dropbox; secrets do not
- Optional “always trust host keys” exists for labs you fully control, and is off by default

## Requirements

- macOS 14+
- Swift 6.2+ command line tools
- GitHub SSH access (`git@github.com`) for package resolve

Full Xcode is not required.

## Run

```bash
cd hostpane
swift run HostpaneCheck
./scripts/package-app.sh
open /Applications/Hostpane.app
```

Debug without bundling:

```bash
swift run Hostpane
```

## Disk image

Every push to `main` publishes an Apple Silicon DMG on the [`latest` GitHub Release](https://github.com/weijing24/hostpane/releases/tag/latest).

```bash
./scripts/package-dmg.sh
```

Installs `/Applications/Hostpane.app`, writes `dist/Hostpane-<version>-<arch>.dmg`, and copies the dmg to `~/Dropbox` when that folder exists. First launch on another Mac: right-click Open, or `xattr -cr /Applications/Hostpane.app`. The binary is ad-hoc signed, not notarized.

If an older copy crashed on launch with `NSBundle.module`, replace it with a build from this script. That crash was a missing resource bundle, not signing.

## Usage

1. Add a host, or import `Host` aliases from `~/.ssh/config`.
2. Connect. Auth tries SSH agent and default keys, or a saved Keychain password / key file.
3. Open the machine card for metrics. Terminal and SFTP are separate sessions from the toolbar buttons.

## License

GNU Affero General Public License v3.0 or later. See [LICENSE](LICENSE).
