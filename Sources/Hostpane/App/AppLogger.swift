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
        stampFormatter.string(from: date)
    }

    static func parse(_ raw: String) -> AppLogLine? {
        guard raw.first == "[" else { return nil }
        let fields = bracketFields(raw, count: 3)
        guard fields.count >= 3, let date = stampFormatter.date(from: fields[0]) else { return nil }
        let level = AppLogLevel(rawValue: fields[1]) ?? .info
        let message = fields.count >= 4 ? fields[3] : ""
        return AppLogLine(timestamp: date, level: level, category: fields[2], message: message)
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func bracketFields(_ raw: String, count: Int) -> [String] {
        var fields: [String] = []
        var rest = Substring(raw)
        for _ in 0..<count {
            guard rest.first == "[", let end = rest.dropFirst().firstIndex(of: "]") else { break }
            fields.append(String(rest[rest.index(after: rest.startIndex)..<end]))
            rest = rest[rest.index(after: end)...]
            if rest.first == " " { rest = rest.dropFirst() }
        }
        if !rest.isEmpty { fields.append(String(rest)) }
        return fields
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

    func recentFileLines(limit: Int = 1000) -> [AppLogLine] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let rows = text.split(separator: "\n", omittingEmptySubsequences: true)
        return rows.suffix(limit).compactMap { AppLogStamp.parse(String($0)) }
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
