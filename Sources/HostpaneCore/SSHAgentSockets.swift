import Foundation
import Traversio

public enum SSHAgentSockets {
    /// Socket paths that may hold identities: `SSH_AUTH_SOCK`, then 1Password.
    public static func available() -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        func add(_ path: String?) {
            guard let path, !path.isEmpty else { return }
            if seen.contains(path) { return }
            seen.insert(path)
            paths.append(path)
        }

        add(ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"])
        let home = FileManager.default.homeDirectoryForCurrentUser
        add(home.appendingPathComponent("Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock").path)
        add(home.appendingPathComponent(".1password/agent.sock").path)
        return paths.filter { FileManager.default.fileExists(atPath: $0) }
    }

    public static func record(from identity: SSHAgentIdentity) -> SSHKeyRecord {
        let blob = Data(identity.publicKey)
        let fingerprint = SSHKeyFile.fingerprint(of: blob)
        let line = opensshLine(type: identity.keyType, blob: blob, comment: identity.comment)
        let name = identity.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return SSHKeyRecord(
            name: name.isEmpty ? fingerprint : name,
            privateKeyPath: "",
            publicKey: line,
            keyType: identity.keyType,
            fingerprint: fingerprint,
            comment: identity.comment,
            origin: .agent
        )
    }

    private static func opensshLine(type: String, blob: Data, comment: String) -> String {
        let encoded = blob.base64EncodedString()
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "\(type) \(encoded)"
        }
        return "\(type) \(encoded) \(trimmed)"
    }
}
