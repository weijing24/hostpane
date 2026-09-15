import AppKit
import Foundation
import Observation

enum AppLogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
}

struct AppLogLine: Identifiable, Equatable, Sendable {
    var id = UUID()
    var timestamp: Date
    var level: AppLogLevel
    var category: String
    var message: String

    var formattedLine: String {
        "[\(AppLogStamp.format(timestamp))] [\(level.rawValue)] [\(category)] \(message)"
    }
}

enum AppLogStamp {
    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

@MainActor
@Observable
final class AppLogger {
    var enabled = true
    var lines: [AppLogLine] = []

    let directoryURL: URL
    var fileURL: URL { directoryURL.appendingPathComponent("hostpane.log") }

    init() {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        directoryURL = logs.appendingPathComponent("Logs/Hostpane", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func debug(_ category: String, _ message: String) { log(.debug, category, message) }
    func info(_ category: String, _ message: String) { log(.info, category, message) }
    func warn(_ category: String, _ message: String) { log(.warn, category, message) }
    func error(_ category: String, _ message: String) { log(.error, category, message) }

    func log(_ level: AppLogLevel, _ category: String, _ message: String) {
        guard enabled else { return }
        let line = AppLogLine(timestamp: Date(), level: level, category: category, message: message)
        lines.append(line)
        if lines.count > 500 {
            lines.removeFirst(lines.count - 500)
        }
        appendToFile(line.formattedLine)
    }

    func clear() {
        lines.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    func revealInFinder() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func openInEditor() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        NSWorkspace.shared.open(fileURL)
    }

    private func appendToFile(_ text: String) {
        rotateIfNeeded()
        let data = Data((text + "\n").utf8)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func rotateIfNeeded() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber else {
            return
        }
        let limit: UInt64 = 5 * 1024 * 1024
        guard size.uint64Value > limit else { return }
        let stamp = AppLogStamp.format(Date()).replacingOccurrences(of: ":", with: "-")
        let rotated = directoryURL.appendingPathComponent("hostpane-\(stamp).log")
        try? FileManager.default.moveItem(at: fileURL, to: rotated)
        pruneOldLogs()
    }

    private func pruneOldLogs() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let rotated = files.filter { $0.lastPathComponent.hasPrefix("hostpane-") && $0.pathExtension == "log" }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        for extra in rotated.dropFirst(5) {
            try? FileManager.default.removeItem(at: extra)
        }
    }
}
