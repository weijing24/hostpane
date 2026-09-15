import Foundation

public enum AppearancePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

public enum TextFileOpener: String, Codable, CaseIterable, Sendable, Identifiable {
    case builtIn
    case defaultApp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .builtIn: return "内置编辑器"
        case .defaultApp: return "系统默认应用"
        }
    }
}

public enum SessionToolbarMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case iconAndText
    case iconOnly
    case textOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .iconAndText: return "图标和文本"
        case .iconOnly: return "仅图标"
        case .textOnly: return "仅文本"
        }
    }
}

public enum TerminalCursorShape: String, Codable, CaseIterable, Sendable, Identifiable {
    case block
    case underline
    case bar

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .block: return "块"
        case .underline: return "下划线"
        case .bar: return "竖线"
        }
    }
}

public enum TerminalInactiveCursor: String, Codable, CaseIterable, Sendable, Identifiable {
    case block
    case underline
    case bar
    case fade

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .block: return "块"
        case .underline: return "下划线"
        case .bar: return "竖线"
        case .fade: return "减弱"
        }
    }
}

public enum TerminalScrollbar: String, Codable, CaseIterable, Sendable, Identifiable {
    case overlay
    case always
    case hidden

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overlay: return "自动隐藏"
        case .always: return "始终显示"
        case .hidden: return "隐藏"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var connectionTimeoutSeconds: Int
    public var alwaysTrustHostKeys: Bool
    public var terminalBellEnabled: Bool
    public var suggestPortForward: Bool
    public var terminalKeepAlive: Bool
    public var terminalKeepAliveSeconds: Int
    public var sftpKeepAlive: Bool
    public var sftpKeepAliveSeconds: Int
    public var sftpShowHiddenFiles: Bool
    public var textFileOpener: TextFileOpener
    public var appearance: AppearancePreference
    public var dashboardHostIDs: [UUID]
    public var sessionToolbarMode: SessionToolbarMode
    public var terminalFontSize: Double
    public var terminalLineSpacing: Double
    public var terminalCursorShape: TerminalCursorShape
    public var terminalCursorBlink: Bool
    public var terminalInactiveCursor: TerminalInactiveCursor
    public var terminalScrollbar: TerminalScrollbar

    public init(
        connectionTimeoutSeconds: Int = 15,
        alwaysTrustHostKeys: Bool = false,
        terminalBellEnabled: Bool = true,
        suggestPortForward: Bool = false,
        terminalKeepAlive: Bool = true,
        terminalKeepAliveSeconds: Int = 10,
        sftpKeepAlive: Bool = true,
        sftpKeepAliveSeconds: Int = 10,
        sftpShowHiddenFiles: Bool = false,
        textFileOpener: TextFileOpener = .builtIn,
        appearance: AppearancePreference = .system,
        dashboardHostIDs: [UUID] = [],
        sessionToolbarMode: SessionToolbarMode = .iconAndText,
        terminalFontSize: Double = 13,
        terminalLineSpacing: Double = 1.0,
        terminalCursorShape: TerminalCursorShape = .block,
        terminalCursorBlink: Bool = true,
        terminalInactiveCursor: TerminalInactiveCursor = .fade,
        terminalScrollbar: TerminalScrollbar = .overlay
    ) {
        self.connectionTimeoutSeconds = connectionTimeoutSeconds
        self.alwaysTrustHostKeys = alwaysTrustHostKeys
        self.terminalBellEnabled = terminalBellEnabled
        self.suggestPortForward = suggestPortForward
        self.terminalKeepAlive = terminalKeepAlive
        self.terminalKeepAliveSeconds = terminalKeepAliveSeconds
        self.sftpKeepAlive = sftpKeepAlive
        self.sftpKeepAliveSeconds = sftpKeepAliveSeconds
        self.sftpShowHiddenFiles = sftpShowHiddenFiles
        self.textFileOpener = textFileOpener
        self.appearance = appearance
        self.dashboardHostIDs = dashboardHostIDs
        self.sessionToolbarMode = sessionToolbarMode
        self.terminalFontSize = terminalFontSize
        self.terminalLineSpacing = terminalLineSpacing
        self.terminalCursorShape = terminalCursorShape
        self.terminalCursorBlink = terminalCursorBlink
        self.terminalInactiveCursor = terminalInactiveCursor
        self.terminalScrollbar = terminalScrollbar
        clamp()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connectionTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .connectionTimeoutSeconds) ?? 15
        alwaysTrustHostKeys = try container.decodeIfPresent(Bool.self, forKey: .alwaysTrustHostKeys) ?? false
        terminalBellEnabled = try container.decodeIfPresent(Bool.self, forKey: .terminalBellEnabled) ?? true
        suggestPortForward = try container.decodeIfPresent(Bool.self, forKey: .suggestPortForward) ?? false
        terminalKeepAlive = try container.decodeIfPresent(Bool.self, forKey: .terminalKeepAlive) ?? true
        terminalKeepAliveSeconds = try container.decodeIfPresent(Int.self, forKey: .terminalKeepAliveSeconds) ?? 10
        sftpKeepAlive = try container.decodeIfPresent(Bool.self, forKey: .sftpKeepAlive) ?? true
        sftpKeepAliveSeconds = try container.decodeIfPresent(Int.self, forKey: .sftpKeepAliveSeconds) ?? 10
        sftpShowHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .sftpShowHiddenFiles) ?? false
        textFileOpener = try container.decodeIfPresent(TextFileOpener.self, forKey: .textFileOpener) ?? .builtIn
        appearance = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? .system
        dashboardHostIDs = try container.decodeIfPresent([UUID].self, forKey: .dashboardHostIDs) ?? []
        sessionToolbarMode = try container.decodeIfPresent(SessionToolbarMode.self, forKey: .sessionToolbarMode) ?? .iconAndText
        terminalFontSize = try container.decodeIfPresent(Double.self, forKey: .terminalFontSize) ?? 13
        terminalLineSpacing = try container.decodeIfPresent(Double.self, forKey: .terminalLineSpacing) ?? 1.0
        terminalCursorShape = try container.decodeIfPresent(TerminalCursorShape.self, forKey: .terminalCursorShape) ?? .block
        terminalCursorBlink = try container.decodeIfPresent(Bool.self, forKey: .terminalCursorBlink) ?? true
        terminalInactiveCursor = try container.decodeIfPresent(TerminalInactiveCursor.self, forKey: .terminalInactiveCursor) ?? .fade
        terminalScrollbar = try container.decodeIfPresent(TerminalScrollbar.self, forKey: .terminalScrollbar) ?? .overlay
        clamp()
    }

    public mutating func clamp() {
        connectionTimeoutSeconds = Self.clampedSeconds(connectionTimeoutSeconds)
        terminalKeepAliveSeconds = Self.clampedSeconds(terminalKeepAliveSeconds)
        sftpKeepAliveSeconds = Self.clampedSeconds(sftpKeepAliveSeconds)
        terminalFontSize = min(max(terminalFontSize, 9), 22)
        terminalLineSpacing = min(max(terminalLineSpacing, 1.0), 1.6)
    }

    public var clamped: AppSettings {
        var copy = self
        copy.clamp()
        return copy
    }

    public static func clampedSeconds(_ value: Int) -> Int {
        min(max(value, 5), 120)
    }

    private enum CodingKeys: String, CodingKey {
        case connectionTimeoutSeconds
        case alwaysTrustHostKeys
        case terminalBellEnabled
        case suggestPortForward
        case terminalKeepAlive
        case terminalKeepAliveSeconds
        case sftpKeepAlive
        case sftpKeepAliveSeconds
        case sftpShowHiddenFiles
        case textFileOpener
        case appearance
        case dashboardHostIDs
        case sessionToolbarMode
        case terminalFontSize
        case terminalLineSpacing
        case terminalCursorShape
        case terminalCursorBlink
        case terminalInactiveCursor
        case terminalScrollbar
    }
}

public enum DashboardHostOrder {
    public static func sorted(_ hosts: [HostRecord], by ids: [UUID]) -> [HostRecord] {
        guard !ids.isEmpty else { return hosts }
        let rank = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        return hosts.enumerated().sorted { lhs, rhs in
            switch (rank[lhs.element.id], rank[rhs.element.id]) {
            case let (left?, right?):
                if left != right { return left < right }
                return lhs.offset < rhs.offset
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}

public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultFileURL()
        }
    }

    public func load() throws -> AppSettings {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return AppSettings() }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return AppSettings() }
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) throws {
        let url = fileURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var next = settings
        next.clamp()
        let data = try JSONEncoder().encode(next)
        try data.write(to: url, options: [.atomic])
    }

    public static func defaultFileURL() -> URL {
        HostStore.applicationSupportDirectory().appendingPathComponent("settings.json")
    }

    public static func previewCacheDirectory() -> URL {
        HostStore.localApplicationSupportDirectory().appendingPathComponent("preview-cache", isDirectory: true)
    }

    @discardableResult
    public static func clearPreviewCache() throws -> Int {
        let directory = previewCacheDirectory()
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let items = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        for item in items {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(item))
        }
        return items.count
    }
}
