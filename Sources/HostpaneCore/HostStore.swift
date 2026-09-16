import Foundation

public struct HostStore: Sendable {
    private let overrideURL: URL?

    public var fileURL: URL {
        overrideURL ?? Self.defaultFileURL()
    }

    public init(fileURL: URL? = nil) {
        overrideURL = fileURL
    }

    public func load() throws -> [HostRecord] {
        guard let data = try SyncedJSON.read(from: fileURL), !data.isEmpty else { return [] }
        return try JSONDecoder().decode([HostRecord].self, from: data)
    }

    public func save(_ hosts: [HostRecord]) throws {
        let data = try JSONEncoder().encode(hosts)
        try SyncedJSON.write(data, to: fileURL)
    }

    public static func applicationSupportDirectory() -> URL {
        ConfigSync.activeDirectory()
    }

    public static func localApplicationSupportDirectory() -> URL {
        ConfigSync.localDirectory()
    }

    public static func defaultFileURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("hosts.json")
    }
}
