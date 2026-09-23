import AppKit
import Darwin
import Foundation
import HostpaneCore
import SwiftUI

@MainActor
final class AppUpdater: NSObject, NSWindowDelegate {
    private var panel: NSWindow?
    private var hosting: NSHostingView<UpdatePanelView>?
    private var task: Task<Void, Never>?
    private var phase: UpdatePhase = .checking
    private var logger: AppLogger?
    private let destination = URL(fileURLWithPath: "/Applications/Hostpane.app", isDirectory: true)

    func checkForUpdates(logger: AppLogger) {
        self.logger = logger
        present()
        if case .downloading = phase { return }
        if case .installing = phase { return }
        task?.cancel()
        task = Task { await performCheck() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if case .installing = phase { return false }
        task?.cancel()
        return true
    }

    private func present() {
        if panel == nil {
            let view = UpdatePanelView(phase: phase, onInstall: { [weak self] in self?.install() }, onClose: { [weak self] in self?.close() })
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "软件更新"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = hosting
            self.hosting = hosting
            panel = window
        }
        render()
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func close() {
        if case .installing = phase { return }
        task?.cancel()
        panel?.orderOut(nil)
    }

    private func install() {
        guard case .available = phase else { return }
        task?.cancel()
        task = Task { await performInstall() }
    }

    private func render() {
        hosting?.rootView = UpdatePanelView(
            phase: phase,
            onInstall: { [weak self] in self?.install() },
            onClose: { [weak self] in self?.close() }
        )
    }

    private func setPhase(_ phase: UpdatePhase) {
        self.phase = phase
        render()
    }

    private func performCheck() async {
        setPhase(.checking)
        do {
            let data = try await Self.latestReleaseData()
            try Task.checkCancellation()
            let release = try AppUpdateFeed.release(from: data)
            guard let current = currentVersion() else {
                setPhase(.failed("无法识别当前版本。"))
                return
            }
            switch AppUpdateFeed.offer(current: current, release: release) {
            case .upToDate(let current, let latest):
                logger?.info("update", "Up to date current=\(current) latest=\(latest)")
                setPhase(.upToDate(current: current.description, latest: latest.description))
            case .available(let release):
                logger?.info("update", "Update available \(release.version.description)")
                pendingRelease = release
                setPhase(.available(version: release.version.description, notes: release.notes))
            }
        } catch is CancellationError {
            return
        } catch let error as AppUpdateParseError {
            logger?.error("update", "Parse failed \(error)")
            setPhase(.failed(Self.message(for: error)))
        } catch {
            logger?.error("update", "Check failed \(error.localizedDescription)")
            setPhase(.failed("无法连接 GitHub。\(error.localizedDescription)"))
        }
    }

    private var pendingRelease: AppRelease?

    private func performInstall() async {
        guard let release = pendingRelease else { return }
        setPhase(.downloading(version: release.version.description))
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("hostpane-update-\(UUID().uuidString)", isDirectory: true)
        var handedOff = false
        defer {
            if !handedOff {
                try? FileManager.default.removeItem(at: work)
            }
        }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let imageName = URL(fileURLWithPath: release.fileName).lastPathComponent
            guard imageName.hasSuffix(".dmg") else {
                throw UpdateTransportError("发布附件不是磁盘映像。")
            }
            let image = work.appendingPathComponent(imageName)
            try await Self.download(release.downloadURL, to: image)
            try Task.checkCancellation()
            setPhase(.installing(version: release.version.description))
            let staged = try Self.extractApp(from: image, work: work)
            let script = try Self.writeInstallScript(in: work)
            let log = logger?.fileURL.path ?? ""
            logger?.info("update", "Handing off install of \(release.version.description)")
            try Self.spawnInstallScript(script, stagedApp: staged, destination: destination, log: log, work: work)
            handedOff = true
            NSApp.terminate(nil)
        } catch is CancellationError {
            setPhase(.available(version: release.version.description, notes: release.notes))
        } catch {
            logger?.error("update", "Install failed \(error.localizedDescription)")
            setPhase(.failed("安装失败。\(error.localizedDescription)"))
        }
    }

    private func currentVersion() -> AppVersion? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return AppVersion(parsing: raw)
    }

    private static func message(for error: AppUpdateParseError) -> String {
        switch error {
        case .malformed:
            return "GitHub 没有返回有效的发布信息。"
        case .unreadableVersion(let tag):
            return "无法识别发布版本号 \(tag)。"
        case .noAppleSiliconDiskImage:
            return "这个版本没有 Apple Silicon 磁盘映像。"
        case .insecureDownloadURL:
            return "下载地址不是 HTTPS。"
        }
    }

    private static func latestReleaseData() async throws -> Data {
        var request = URLRequest(url: AppUpdateFeed.latestReleaseURL)
        request.setValue("Hostpane", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdateTransportError("GitHub 返回了 \(code)。")
        }
        return data
    }

    private static func download(_ url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("Hostpane", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdateTransportError("下载失败（\(code)）。")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        _ = try? run("/usr/bin/xattr", ["-d", "com.apple.quarantine", destination.path])
    }

    private static func extractApp(from image: URL, work: URL) throws -> URL {
        let mount = work.appendingPathComponent("mount", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        do {
            _ = try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, image.path])
        } catch {
            throw UpdateTransportError("无法打开磁盘映像。")
        }
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }
        let source = mount.appendingPathComponent("Hostpane.app", isDirectory: true)
        let binary = source.appendingPathComponent("Contents/MacOS/Hostpane")
        guard FileManager.default.fileExists(atPath: binary.path) else {
            throw UpdateTransportError("磁盘映像里没有 Hostpane.app。")
        }
        let stagedDir = work.appendingPathComponent("staged", isDirectory: true)
        try FileManager.default.createDirectory(at: stagedDir, withIntermediateDirectories: true)
        let staged = stagedDir.appendingPathComponent("Hostpane.app", isDirectory: true)
        _ = try run("/usr/bin/ditto", [source.path, staged.path])
        return staged
    }

    private static func writeInstallScript(in work: URL) throws -> URL {
        let url = work.appendingPathComponent("install.sh")
        try installScript.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// The helper has to outlive this process: the running bundle cannot replace itself.
    private static func spawnInstallScript(_ script: URL, stagedApp: URL, destination: URL, log: String, work: URL) throws {
        let arguments = [
            "/bin/sh",
            script.path,
            String(ProcessInfo.processInfo.processIdentifier),
            stagedApp.path,
            destination.path,
            log,
            work.path,
        ]
        var attr: posix_spawnattr_t?
        guard posix_spawnattr_init(&attr) == 0 else {
            throw UpdateTransportError("无法启动安装程序。")
        }
        defer { posix_spawnattr_destroy(&attr) }
        guard posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID)) == 0 else {
            throw UpdateTransportError("无法启动安装程序。")
        }
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = argv.withUnsafeBufferPointer { buffer -> Int32 in
            posix_spawn(&pid, "/bin/sh", nil, &attr, buffer.baseAddress, environ)
        }
        guard spawned == 0 else {
            throw UpdateTransportError("无法启动安装程序（\(spawned)）。")
        }
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let detail = text.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateTransportError(detail.isEmpty ? "\(launchPath) 退出 \(process.terminationStatus)。" : detail)
        }
        return text
    }
}

private struct UpdateTransportError: LocalizedError {
    var errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private let installScript = """
#!/bin/sh
set -eu
pid="$1"
src="$2"
dest="$3"
log="$4"
work="$5"
cd /tmp

logmsg() {
  if [ -n "$log" ]; then
    mkdir -p "$(dirname "$log")"
    printf '[%s] [INFO] [update] %s\\n' "$(date '+%Y-%m-%d %H:%M:%S.000')" "$1" >> "$log"
  fi
}

fail() {
  logmsg "install failed: $1"
  if [ -d "$dest" ]; then
    /usr/bin/open "$dest" || true
  fi
  exit 1
}

logmsg "waiting for pid $pid"
while kill -0 "$pid" 2>/dev/null; do
  sleep 0.2
done
sleep 0.4

stage="${dest}.incoming"
rm -rf "$stage"
/usr/bin/ditto "$src" "$stage" || fail "ditto failed"
/usr/bin/xattr -cr "$stage" >/dev/null 2>&1 || true
/usr/bin/codesign --force --sign - "$stage" >/dev/null 2>&1 || fail "codesign failed"
rm -rf "$dest" || fail "could not remove the installed app"
mv "$stage" "$dest" || fail "could not move the new app into place"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$lsregister" ]; then
  "$lsregister" -f "$dest" >/dev/null 2>&1 || true
fi
logmsg "installed $dest"
/usr/bin/open "$dest" || fail "could not open the new app"
rm -rf "$work"
"""
