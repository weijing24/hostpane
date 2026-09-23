import Foundation

public struct SnippetPackage: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var note: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, note: String = "", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

public struct CodeSnippet: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var packageID: UUID?
    public var name: String
    public var body: String
    public var note: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        packageID: UUID? = nil,
        name: String,
        body: String,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.packageID = packageID
        self.name = name
        self.body = body
        self.note = note
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        packageID = try container.decodeIfPresent(UUID.self, forKey: .packageID)
        name = try container.decode(String.self, forKey: .name)
        body = try container.decode(String.self, forKey: .body)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

public struct SnippetRun: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var snippetID: UUID
    public var startedAt: Date
    public var summary: String
    public var output: String

    public init(id: UUID = UUID(), snippetID: UUID, startedAt: Date = Date(), summary: String, output: String) {
        self.id = id
        self.snippetID = snippetID
        self.startedAt = startedAt
        self.summary = summary
        self.output = output
    }
}

public struct SnippetLibrary: Codable, Equatable, Sendable {
    public var packages: [SnippetPackage]
    public var snippets: [CodeSnippet]
    public var runs: [SnippetRun]

    public init(
        packages: [SnippetPackage] = [],
        snippets: [CodeSnippet] = [],
        runs: [SnippetRun] = []
    ) {
        self.packages = packages
        self.snippets = snippets
        self.runs = runs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packages = try container.decodeIfPresent([SnippetPackage].self, forKey: .packages) ?? []
        snippets = try container.decodeIfPresent([CodeSnippet].self, forKey: .snippets) ?? []
        runs = try container.decodeIfPresent([SnippetRun].self, forKey: .runs) ?? []
    }
}

public struct SnippetStore: Sendable {
    private let overrideURL: URL?

    public var fileURL: URL {
        overrideURL ?? Self.defaultFileURL()
    }

    public init(fileURL: URL? = nil) {
        overrideURL = fileURL
    }

    public func load() throws -> SnippetLibrary {
        guard let data = try SyncedJSON.read(from: fileURL), !data.isEmpty else {
            return SnippetLibrary()
        }
        return try JSONDecoder().decode(SnippetLibrary.self, from: data)
    }

    public func save(_ library: SnippetLibrary) throws {
        let data = try JSONEncoder().encode(library)
        try SyncedJSON.write(data, to: fileURL)
    }

    public static func defaultFileURL() -> URL {
        HostStore.applicationSupportDirectory().appendingPathComponent("snippets.json")
    }
}
