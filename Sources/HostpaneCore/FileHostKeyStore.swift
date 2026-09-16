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

    private let overrideURL: URL?
    private var rows: [Row] = []

    public init(url: URL? = nil) {
        overrideURL = url
    }

    private var url: URL {
        overrideURL ?? HostStore.applicationSupportDirectory().appendingPathComponent("known-hosts.json")
    }

    public func lookupHostKey(
        endpointHost: String,
        endpointPort: UInt16
    ) async throws -> SSHTrustedHostKey? {
        loadFromDisk()
        guard let row = rows.first(where: { $0.host == endpointHost && $0.port == endpointPort }) else {
            return nil
        }
        return try SSHTrustedHostKey(rawRepresentation: [UInt8](row.key))
    }

    public func storeHostKey(_ request: SSHHostKeyStoreRequest) async throws {
        loadFromDisk()
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

    private func loadFromDisk() {
        if let data = try? SyncedJSON.read(from: url),
           !data.isEmpty,
           let decoded = try? JSONDecoder().decode([Row].self, from: data) {
            rows = decoded
        } else {
            rows = []
        }
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(rows)
        try SyncedJSON.write(data, to: url)
    }
}
