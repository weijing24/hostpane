import Foundation
import Traversio

/// App-owned TOFU store. Traversio's `knownHostsFile` refuses to connect when
/// the alias is missing from `~/.ssh/known_hosts`; this machine has no such file.
public actor FileHostKeyStore: SSHHostKeyTrustStore {
    private struct Row: Codable {
        var host: String
        var port: UInt16
        var key: Data
    }

    private let url: URL
    private var rows: [Row]

    public init(url: URL = HostStore.applicationSupportDirectory().appendingPathComponent("known-hosts.json")) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Row].self, from: data) {
            self.rows = decoded
        } else {
            self.rows = []
        }
    }

    public func lookupHostKey(
        endpointHost: String,
        endpointPort: UInt16
    ) async throws -> SSHTrustedHostKey? {
        guard let row = rows.first(where: { $0.host == endpointHost && $0.port == endpointPort }) else {
            return nil
        }
        return try SSHTrustedHostKey(rawRepresentation: [UInt8](row.key))
    }

    public func storeHostKey(_ request: SSHHostKeyStoreRequest) async throws {
        let row = Row(
            host: request.endpointHost,
            port: request.endpointPort,
            key: Data(request.trustedHostKey.rawRepresentation)
        )
        if let index = rows.firstIndex(where: { $0.host == row.host && $0.port == row.port }) {
            rows[index] = row
        } else {
            rows.append(row)
        }
        try persist()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(rows)
        try data.write(to: url, options: [.atomic])
    }
}
