import Foundation

public enum ConfigSyncDestination: String, CaseIterable, Sendable, Identifiable {
    case local
    case iCloud
    case dropbox

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .local: return "仅本机"
        case .iCloud: return "iCloud Drive"
        case .dropbox: return "Dropbox"
        }
    }

    public var statusSymbol: String {
        switch self {
        case .local: return "internaldrive"
        case .iCloud: return "icloud"
        case .dropbox: return "externaldrive.badge.icloud"
        }
    }
}

public enum ConfigSync {
    public static let defaultsKey = "hostpane.configSyncDestination"
    public static let syncedFileNames = [
        "hosts.json",
        "settings.json",
        "keys.json",
        "known-hosts.json"
    ]

    public static var destination: ConfigSyncDestination {
        get {
            ConfigSyncDestination(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .local
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    public static func activeDirectory() -> URL {
        migrateLegacyDropboxIfNeeded()
        return (try? directory(for: destination)) ?? localDirectory()
    }

    public static func localDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return root.appendingPathComponent("Hostpane", isDirectory: true)
    }

    public static func directory(for destination: ConfigSyncDestination) throws -> URL {
        switch destination {
        case .local:
            return localDirectory()
        case .iCloud:
            guard let root = iCloudDriveRoot() else {
                throw ConfigSyncError.iCloudUnavailable
            }
            return root.appendingPathComponent("Hostpane", isDirectory: true)
        case .dropbox:
            guard let root = dropboxRoot() else {
                throw ConfigSyncError.dropboxUnavailable
            }
            return root
                .appendingPathComponent("Apps", isDirectory: true)
                .appendingPathComponent("Hostpane", isDirectory: true)
        }
    }

    public static func iCloudDriveRoot() -> URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return existingDirectory(url)
    }

    public static func dropboxRoot() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/CloudStorage/Dropbox"),
            home.appendingPathComponent("Dropbox")
        ]
        return candidates.compactMap(existingDirectory).first
    }

    public static func statusText(for destination: ConfigSyncDestination) -> String {
        switch destination {
        case .local:
            return "同步未开始"
        case .iCloud:
            return iCloudDriveRoot() == nil ? "iCloud Drive 不可用" : "iCloud Drive 已就绪"
        case .dropbox:
            return dropboxRoot() == nil ? "未找到 Dropbox 文件夹" : "Dropbox 已就绪"
        }
    }

    public static func migrateLegacyDropboxIfNeeded() {
        guard destination == .dropbox, let root = dropboxRoot() else { return }
        let legacy = root.appendingPathComponent("Hostpane", isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        guard let dest = try? directory(for: .dropbox) else { return }
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for name in syncedFileNames {
            let from = legacy.appendingPathComponent(name)
            let to = dest.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            if FileManager.default.fileExists(atPath: to.path) { continue }
            try? FileManager.default.copyItem(at: from, to: to)
        }
    }

    public static func apply(_ next: ConfigSyncDestination) throws {
        migrateLegacyDropboxIfNeeded()
        let current = destination
        if current == next { return }
        let source = (try? directory(for: current)) ?? localDirectory()
        let dest = try directory(for: next)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for name in syncedFileNames {
            let from = source.appendingPathComponent(name)
            let to = dest.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            if FileManager.default.fileExists(atPath: to.path) {
                try FileManager.default.removeItem(at: to)
            }
            try FileManager.default.copyItem(at: from, to: to)
        }
        destination = next
    }

    private static func existingDirectory(_ url: URL) -> URL? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return url
    }
}

public enum ConfigSyncError: Error, LocalizedError {
    case iCloudUnavailable
    case dropboxUnavailable

    public var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "没有找到 iCloud Drive。请在系统设置里打开 iCloud Drive。"
        case .dropboxUnavailable:
            return "没有找到 Dropbox 文件夹。"
        }
    }
}
