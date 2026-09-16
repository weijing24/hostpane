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

public struct ConfigSyncInventory: Equatable, Sendable {
    public var hostCount: Int
    public var keyCount: Int
    public var hasSettings: Bool
    public var hasKnownHosts: Bool

    public init(hostCount: Int, keyCount: Int, hasSettings: Bool, hasKnownHosts: Bool) {
        self.hostCount = hostCount
        self.keyCount = keyCount
        self.hasSettings = hasSettings
        self.hasKnownHosts = hasKnownHosts
    }

    public var isEmpty: Bool {
        hostCount == 0 && keyCount == 0 && !hasSettings && !hasKnownHosts
    }

    public func summaryLabel() -> String {
        var parts: [String] = []
        if hostCount > 0 { parts.append("\(hostCount) 台主机") }
        if keyCount > 0 { parts.append("\(keyCount) 把密钥") }
        if hasSettings { parts.append("设置") }
        if hasKnownHosts { parts.append("已知主机密钥") }
        return parts.isEmpty ? "空" : parts.joined(separator: "、")
    }
}

public enum ConfigSyncPlan: Equatable, Sendable {
    case alreadyCurrent
    case switchOnly
    case seedEmptyDestination
    case confirm(source: ConfigSyncInventory, destination: ConfigSyncInventory)
}

public enum ConfigSyncChoice: Sendable {
    case keepSource
    case keepDestination
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

    public static func inventory(at directory: URL) -> ConfigSyncInventory {
        let hosts = (try? HostStore(fileURL: directory.appendingPathComponent("hosts.json")).load()) ?? []
        let keys = (try? KeyStore(fileURL: directory.appendingPathComponent("keys.json")).load()) ?? []
        return ConfigSyncInventory(
            hostCount: hosts.count,
            keyCount: keys.count,
            hasSettings: fileExistsWithContent(directory.appendingPathComponent("settings.json")),
            hasKnownHosts: fileExistsWithContent(directory.appendingPathComponent("known-hosts.json"))
        )
    }

    public static func plan(from source: URL, to destination: URL) -> ConfigSyncPlan {
        if source.standardizedFileURL == destination.standardizedFileURL {
            return .switchOnly
        }
        let sourceInventory = inventory(at: source)
        let destinationInventory = inventory(at: destination)
        if contentsMatch(source, destination) {
            return .switchOnly
        }
        if destinationInventory.isEmpty {
            return sourceInventory.isEmpty ? .switchOnly : .seedEmptyDestination
        }
        if sourceInventory.isEmpty {
            return .switchOnly
        }
        return .confirm(source: sourceInventory, destination: destinationInventory)
    }

    public static func plan(switchingTo next: ConfigSyncDestination) throws -> ConfigSyncPlan {
        if destination == next { return .alreadyCurrent }
        let source = (try? directory(for: destination)) ?? localDirectory()
        let dest = try directory(for: next)
        return plan(from: source, to: dest)
    }

    public static func execute(from source: URL, to destination: URL, choice: ConfigSyncChoice?) throws {
        switch plan(from: source, to: destination) {
        case .alreadyCurrent, .switchOnly:
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        case .seedEmptyDestination:
            try copySyncedFiles(from: source, to: destination, replaceMissing: false)
        case .confirm:
            guard let choice else { throw ConfigSyncError.confirmationRequired }
            switch choice {
            case .keepSource:
                try copySyncedFiles(from: source, to: destination, replaceMissing: true)
            case .keepDestination:
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            }
        }
    }

    public static func apply(_ next: ConfigSyncDestination, choice: ConfigSyncChoice? = nil) throws {
        migrateLegacyDropboxIfNeeded()
        if destination == next { return }
        let source = (try? directory(for: destination)) ?? localDirectory()
        let dest = try directory(for: next)
        try execute(from: source, to: dest, choice: choice)
        destination = next
    }

    public static func conflictCopyNames(in directory: URL) -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return items.filter { name in
            let lower = name.lowercased()
            return lower.contains("conflicted copy") || name.contains("冲突副本")
        }.sorted()
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

    private static func copySyncedFiles(from source: URL, to destination: URL, replaceMissing: Bool) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in syncedFileNames {
            let from = source.appendingPathComponent(name)
            let to = destination.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: from.path) {
                let data = try SyncedJSON.read(from: from) ?? Data()
                try SyncedJSON.write(data, to: to)
            } else if replaceMissing {
                try SyncedJSON.removeItem(at: to)
            }
        }
    }

    private static func contentsMatch(_ source: URL, _ destination: URL) -> Bool {
        let sourceHosts = (try? HostStore(fileURL: source.appendingPathComponent("hosts.json")).load()) ?? []
        let destHosts = (try? HostStore(fileURL: destination.appendingPathComponent("hosts.json")).load()) ?? []
        guard sourceHosts == destHosts else { return false }
        let sourceKeys = (try? KeyStore(fileURL: source.appendingPathComponent("keys.json")).load()) ?? []
        let destKeys = (try? KeyStore(fileURL: destination.appendingPathComponent("keys.json")).load()) ?? []
        guard sourceKeys == destKeys else { return false }
        let sourceSettings = (try? SettingsStore(fileURL: source.appendingPathComponent("settings.json")).load()) ?? AppSettings()
        let destSettings = (try? SettingsStore(fileURL: destination.appendingPathComponent("settings.json")).load()) ?? AppSettings()
        guard sourceSettings == destSettings else { return false }
        let sourceKnown = (try? SyncedJSON.read(from: source.appendingPathComponent("known-hosts.json"))) ?? Data()
        let destKnown = (try? SyncedJSON.read(from: destination.appendingPathComponent("known-hosts.json"))) ?? Data()
        return sourceKnown == destKnown
    }

    private static func fileExistsWithContent(_ url: URL) -> Bool {
        guard let data = try? SyncedJSON.read(from: url) else { return false }
        return !data.isEmpty
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
    case confirmationRequired

    public var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "没有找到 iCloud Drive。请在系统设置里打开 iCloud Drive。"
        case .dropboxUnavailable:
            return "没有找到 Dropbox 文件夹。"
        case .confirmationRequired:
            return "两边的数据不一样，需要先选择保留哪一份。"
        }
    }
}

enum SyncedJSON {
    static func read(from url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var coordError: NSError?
        var readError: Error?
        var result: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { url in
            do {
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                result = try Data(contentsOf: url)
            } catch {
                readError = error
            }
        }
        if let coordError { throw coordError }
        if let readError { throw readError }
        return result
    }

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { url in
            do {
                try data.write(to: url, options: [.atomic])
            } catch {
                writeError = error
            }
        }
        if let coordError { throw coordError }
        if let writeError { throw writeError }
    }

    static func removeItem(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { url in
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
                writeError = error
            }
        }
        if let coordError { throw coordError }
        if let writeError { throw writeError }
    }
}
