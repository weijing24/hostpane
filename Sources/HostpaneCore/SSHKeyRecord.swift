import Foundation

public enum SSHKeyOrigin: String, Codable, Sendable {
    case file
    case generated
    case clipboard
    case agent
}

public struct SSHKeyRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var privateKeyPath: String
    public var publicKeyPath: String?
    public var publicKey: String
    public var keyType: String
    public var fingerprint: String
    public var comment: String
    public var createdAt: Date
    public var origin: SSHKeyOrigin

    public init(
        id: UUID = UUID(),
        name: String,
        privateKeyPath: String = "",
        publicKeyPath: String? = nil,
        publicKey: String = "",
        keyType: String,
        fingerprint: String,
        comment: String = "",
        createdAt: Date = Date(),
        origin: SSHKeyOrigin = .file
    ) {
        self.id = id
        self.name = name
        self.privateKeyPath = privateKeyPath
        self.publicKeyPath = publicKeyPath
        self.publicKey = publicKey
        self.keyType = keyType
        self.fingerprint = fingerprint
        self.comment = comment
        self.createdAt = createdAt
        self.origin = origin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath) ?? ""
        publicKeyPath = try container.decodeIfPresent(String.self, forKey: .publicKeyPath)
        publicKey = try container.decodeIfPresent(String.self, forKey: .publicKey) ?? ""
        keyType = try container.decode(String.self, forKey: .keyType)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        if let origin = try container.decodeIfPresent(SSHKeyOrigin.self, forKey: .origin) {
            self.origin = origin
        } else if privateKeyPath.isEmpty {
            origin = .clipboard
        } else {
            origin = .file
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(privateKeyPath, forKey: .privateKeyPath)
        try container.encodeIfPresent(publicKeyPath, forKey: .publicKeyPath)
        try container.encode(publicKey, forKey: .publicKey)
        try container.encode(keyType, forKey: .keyType)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encode(comment, forKey: .comment)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(origin, forKey: .origin)
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !comment.isEmpty { return comment }
        if !privateKeyPath.isEmpty {
            return URL(fileURLWithPath: privateKeyPath).lastPathComponent
        }
        return fingerprint
    }

    public var hasPrivateKeyFile: Bool {
        !privateKeyPath.isEmpty && FileManager.default.isReadableFile(atPath: privateKeyPath)
    }

    public var shortType: String {
        let raw = keyType.lowercased()
        if raw.contains("ed25519") { return "ED25519" }
        if raw.contains("rsa") { return "RSA" }
        if raw.contains("ecdsa") { return "ECDSA" }
        if raw.contains("dss") || raw.contains("dsa") { return "DSA" }
        return keyType.uppercased()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case privateKeyPath
        case publicKeyPath
        case publicKey
        case keyType
        case fingerprint
        case comment
        case createdAt
        case origin
    }
}

public struct KeyStore: Sendable {
    private let overrideURL: URL?

    public var fileURL: URL {
        overrideURL ?? HostStore.applicationSupportDirectory().appendingPathComponent("keys.json")
    }

    public init(fileURL: URL? = nil) {
        overrideURL = fileURL
    }

    public func load() throws -> [SSHKeyRecord] {
        guard let data = try SyncedJSON.read(from: fileURL), !data.isEmpty else { return [] }
        return try JSONDecoder().decode([SSHKeyRecord].self, from: data)
    }

    public func save(_ keys: [SSHKeyRecord]) throws {
        let data = try JSONEncoder().encode(keys)
        try SyncedJSON.write(data, to: fileURL)
    }
}
