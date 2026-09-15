import Foundation

public enum AuthKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case agent
    case privateKey
    case password

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .agent: return "SSH agent"
        case .privateKey: return "私钥"
        case .password: return "密码"
        }
    }
}

public enum HostConnectionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case ssh

    public var id: String { rawValue }

    public var title: String { "SSH" }
}

public struct HostRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var hostname: String
    public var port: Int
    public var username: String
    public var authKind: AuthKind
    public var privateKeyPath: String?
    public var createdAt: Date
    public var connectionKind: HostConnectionKind
    public var group: String?
    public var tags: [String]
    public var notes: String
    public var showOnDashboard: Bool
    public var defaultSFTPPath: String
    public var sshKeyFingerprint: String?
    public var hideAddress: Bool
    public var defaultInterface: String?
    public var defaultMount: String?

    public init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: Int = 22,
        username: String,
        authKind: AuthKind = .agent,
        privateKeyPath: String? = nil,
        createdAt: Date = Date(),
        connectionKind: HostConnectionKind = .ssh,
        group: String? = nil,
        tags: [String] = [],
        notes: String = "",
        showOnDashboard: Bool = true,
        defaultSFTPPath: String = "/",
        sshKeyFingerprint: String? = nil,
        hideAddress: Bool = false,
        defaultInterface: String? = nil,
        defaultMount: String? = nil
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.authKind = authKind
        self.privateKeyPath = privateKeyPath
        self.createdAt = createdAt
        self.connectionKind = connectionKind
        self.group = Self.normalizedGroup(group)
        self.tags = Self.normalizedTags(tags)
        self.notes = notes
        self.showOnDashboard = showOnDashboard
        self.defaultSFTPPath = Self.normalizedSFTPPath(defaultSFTPPath)
        self.sshKeyFingerprint = Self.normalizedFingerprint(sshKeyFingerprint)
        self.hideAddress = hideAddress
        self.defaultInterface = Self.normalizedGroup(defaultInterface)
        self.defaultMount = Self.normalizedGroup(defaultMount)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        hostname = try container.decode(String.self, forKey: .hostname)
        port = try container.decode(Int.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        authKind = try container.decode(AuthKind.self, forKey: .authKind)
        privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        connectionKind = try container.decodeIfPresent(HostConnectionKind.self, forKey: .connectionKind) ?? .ssh
        group = Self.normalizedGroup(try container.decodeIfPresent(String.self, forKey: .group))
        tags = Self.normalizedTags(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        showOnDashboard = try container.decodeIfPresent(Bool.self, forKey: .showOnDashboard) ?? true
        defaultSFTPPath = Self.normalizedSFTPPath(
            try container.decodeIfPresent(String.self, forKey: .defaultSFTPPath) ?? "/"
        )
        sshKeyFingerprint = Self.normalizedFingerprint(
            try container.decodeIfPresent(String.self, forKey: .sshKeyFingerprint)
        )
        hideAddress = try container.decodeIfPresent(Bool.self, forKey: .hideAddress) ?? false
        defaultInterface = Self.normalizedGroup(try container.decodeIfPresent(String.self, forKey: .defaultInterface))
        defaultMount = Self.normalizedGroup(try container.decodeIfPresent(String.self, forKey: .defaultMount))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(hostname, forKey: .hostname)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(authKind, forKey: .authKind)
        try container.encodeIfPresent(privateKeyPath, forKey: .privateKeyPath)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(connectionKind, forKey: .connectionKind)
        try container.encodeIfPresent(group, forKey: .group)
        try container.encode(tags, forKey: .tags)
        try container.encode(notes, forKey: .notes)
        try container.encode(showOnDashboard, forKey: .showOnDashboard)
        try container.encode(defaultSFTPPath, forKey: .defaultSFTPPath)
        try container.encodeIfPresent(sshKeyFingerprint, forKey: .sshKeyFingerprint)
        try container.encode(hideAddress, forKey: .hideAddress)
        try container.encodeIfPresent(defaultInterface, forKey: .defaultInterface)
        try container.encodeIfPresent(defaultMount, forKey: .defaultMount)
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? hostname : trimmed
    }

    public var sshPort: UInt16 {
        let clamped = min(max(port, 1), 65_535)
        return UInt16(clamped)
    }

    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    public static func normalizedGroup(_ group: String?) -> String? {
        guard let group else { return nil }
        let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func normalizedSFTPPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "/" : trimmed
    }

    public static func normalizedFingerprint(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case hostname
        case port
        case username
        case authKind
        case privateKeyPath
        case createdAt
        case connectionKind
        case group
        case tags
        case notes
        case showOnDashboard
        case defaultSFTPPath
        case sshKeyFingerprint
        case hideAddress
        case defaultInterface
        case defaultMount
    }
}
