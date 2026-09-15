import CryptoKit
import Foundation

public enum SSHKeyError: Error, LocalizedError, Equatable {
    case fileExists(String)
    case missingPublicKey(String)
    case invalidPublicKey
    case sshKeygenFailed(String)
    case unreadableFile(String)

    public var errorDescription: String? {
        switch self {
        case .fileExists(let path):
            return "A key already exists at \(path)."
        case .missingPublicKey(let path):
            return "No public key next to \(path)."
        case .invalidPublicKey:
            return "The public key file is not a valid OpenSSH key."
        case .sshKeygenFailed(let message):
            return message
        case .unreadableFile(let path):
            return "Could not read \(path)."
        }
    }
}

public enum SSHKeyFile {
    public static func inspect(privateKeyPath: String) throws -> SSHKeyRecord {
        if privateKeyPath.hasSuffix(".pub") {
            return try inspectPublicKeyFile(path: privateKeyPath)
        }
        let privateURL = URL(fileURLWithPath: privateKeyPath)
        let publicPath = privateKeyPath + ".pub"
        let line: String
        var storedPublicPath: String?
        if FileManager.default.isReadableFile(atPath: publicPath) {
            storedPublicPath = publicPath
            let file = try String(contentsOfFile: publicPath, encoding: .utf8)
            guard let first = publicKeyLines(in: file).first else {
                throw SSHKeyError.invalidPublicKey
            }
            line = first
        } else if let derived = try? derivePublicKey(fromPrivateKeyPath: privateKeyPath) {
            line = derived
        } else {
            throw SSHKeyError.missingPublicKey(privateKeyPath)
        }
        guard let parsed = parsePublicKeyLine(line) else {
            throw SSHKeyError.invalidPublicKey
        }
        return SSHKeyRecord(
            name: privateURL.lastPathComponent,
            privateKeyPath: privateKeyPath,
            publicKeyPath: storedPublicPath,
            publicKey: line,
            keyType: parsed.type,
            fingerprint: parsed.fingerprint,
            comment: parsed.comment,
            origin: .file
        )
    }

    public static func inspectPublicKeyFile(path: String) throws -> SSHKeyRecord {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        guard let record = records(fromPublicKeyText: text, origin: .file).first else {
            throw SSHKeyError.invalidPublicKey
        }
        var next = record
        next.publicKeyPath = path
        next.name = URL(fileURLWithPath: path).lastPathComponent
        return next
    }

    public static func records(fromPublicKeyText text: String, origin: SSHKeyOrigin) -> [SSHKeyRecord] {
        publicKeyLines(in: text).compactMap { line in
            guard let parsed = parsePublicKeyLine(line) else { return nil }
            let name = parsed.comment.isEmpty ? parsed.fingerprint : parsed.comment
            return SSHKeyRecord(
                name: name,
                privateKeyPath: "",
                publicKey: line,
                keyType: parsed.type,
                fingerprint: parsed.fingerprint,
                comment: parsed.comment,
                origin: origin
            )
        }
    }

    public static func publicKeyLines(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty && !line.hasPrefix("#") && parsePublicKeyLine(line) != nil
            }
    }

    public static func looksLikePublicKey(_ text: String) -> Bool {
        !publicKeyLines(in: text).isEmpty
    }

    public static func fingerprint(of blob: Data) -> String {
        let digest = SHA256.hash(data: blob)
        let encoded = Data(digest).base64EncodedString()
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:\(encoded)"
    }

    public static func derivePublicKey(fromPrivateKeyPath path: String, passphrase: String = "") throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-y", "-f", path, "-P", passphrase]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus != 0 || output.isEmpty {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHKeyError.sshKeygenFailed(message?.isEmpty == false ? message! : "ssh-keygen -y failed.")
        }
        guard let line = publicKeyLines(in: output).first ?? (parsePublicKeyLine(output) != nil ? output : nil) else {
            throw SSHKeyError.invalidPublicKey
        }
        return line
    }

    public static func scanDefaultDirectory(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
    ) throws -> [SSHKeyRecord] {
        let skip = Set([
            "config", "known_hosts", "known_hosts.old", "authorized_keys",
            "authorized_keys2", "config.d"
        ])
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let items = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        var records: [SSHKeyRecord] = []
        for name in items.sorted() {
            if name.hasPrefix(".") || skip.contains(name) { continue }
            if name.hasSuffix(".pub") { continue }
            let path = directory.appendingPathComponent(name).path
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            if let record = try? inspect(privateKeyPath: path) {
                records.append(record)
            }
        }
        return records
    }

    public static func generateEd25519(
        name: String,
        directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh"),
        comment: String,
        passphrase: String
    ) throws -> SSHKeyRecord {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = trimmed.isEmpty ? "id_ed25519_hostpane" : trimmed
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let privateURL = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: privateURL.path) {
            throw SSHKeyError.fileExists(privateURL.path)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = [
            "-t", "ed25519",
            "-f", privateURL.path,
            "-C", comment,
            "-N", passphrase,
            "-q"
        ]
        let stderr = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHKeyError.sshKeygenFailed(message?.isEmpty == false ? message! : "ssh-keygen failed.")
        }
        var record = try inspect(privateKeyPath: privateURL.path)
        record.name = fileName
        record.origin = .generated
        return record
    }

    public static func parsePublicKeyLine(_ line: String) -> (type: String, fingerprint: String, comment: String)? {
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard parts.count >= 2, let blob = Data(base64Encoded: parts[1]) else { return nil }
        let digest = SHA256.hash(data: blob)
        let encoded = Data(digest).base64EncodedString()
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        let comment = parts.dropFirst(2).joined(separator: " ")
        return (parts[0], "SHA256:\(encoded)", comment)
    }
}
