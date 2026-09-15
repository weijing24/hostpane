import Foundation

public struct HostStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultFileURL()
        }
    }

    public func load() throws -> [HostRecord] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [] }
        return try JSONDecoder().decode([HostRecord].self, from: data)
    }

    public func save(_ hosts: [HostRecord]) throws {
        let url = fileURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(hosts)
        try data.write(to: url, options: [.atomic])
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
