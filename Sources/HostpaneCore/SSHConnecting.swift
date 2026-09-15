import Foundation
import Traversio

public enum SSHKeepAliveMode: Sendable {
    case terminal
    case sftp
    case docker
}

public struct SSHSecretOverrides: Sendable {
    public var password: String?
    public var passphrase: String?

    public init(password: String? = nil, passphrase: String? = nil) {
        self.password = password
        self.passphrase = passphrase
    }
}

public enum HostpaneSSHError: Error, LocalizedError {
    case invalidPort
    case missingHostname
    case missingUsername
    case missingPassword
    case missingPrivateKey
    case noAuthenticationMethods
    case notConnected
    case unsupportedOS(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "端口必须在 1 到 65535 之间。"
        case .missingHostname:
            return "需要填写主机名。"
        case .missingUsername:
            return "需要填写用户名。"
        case .missingPassword:
            return "没有为这台机器保存密码。"
        case .missingPrivateKey:
            return "私钥文件不存在或无法读取。"
        case .noAuthenticationMethods:
            return "没有可用的 SSH 认证方式。请启动 ssh-agent、选择密钥，或保存密码。"
        case .notConnected:
            return "尚未连接。"
        case .unsupportedOS(let name):
            return "当前只解析 Linux /proc 指标。远程系统是 \(name)。"
        }
    }
}

public actor SSHEngine {
    private var connection: SSHConnection?
    private var agent: SSHAgentClient?
    private let hostKeyStore = FileHostKeyStore()
    private let sshConfig = SSHConfigImporter()

    public init() {}

    public var isConnected: Bool {
        get async { connection != nil }
    }

    public func connect(
        host: HostRecord,
        secrets: SecretStore,
        overrides: SSHSecretOverrides = SSHSecretOverrides(),
        settings: AppSettings = AppSettings(),
        keepAlive: SSHKeepAliveMode = .terminal,
        onLog: @escaping @Sendable (SSHClientLogEvent) -> Void = { _ in }
    ) async throws {
        await close()
        let configuration = try await makeConfiguration(
            host: host,
            secrets: secrets,
            overrides: overrides,
            settings: settings,
            keepAlive: keepAlive
        )
        let handler = SSHClientLogHandler.sink(minimumLevel: .info, onLog)
        connection = try await SSHClient.connect(configuration: configuration, logHandler: handler)
    }

    public func execute(_ command: String) async throws -> SSHExecResult {
        guard let connection else { throw HostpaneSSHError.notConnected }
        return try await connection.execute(command)
    }

    public func openShell(columns: UInt32, rows: UInt32) async throws -> SSHSession {
        guard let connection else { throw HostpaneSSHError.notConnected }
        var request = SSHPseudoTerminalRequest.default
        request = SSHPseudoTerminalRequest(
            terminalType: "xterm-256color",
            characterWidth: columns,
            characterHeight: rows,
            pixelWidth: request.pixelWidth,
            pixelHeight: request.pixelHeight,
            encodedTerminalModes: request.encodedTerminalModes
        )
        return try await connection.openShell(pseudoTerminalRequest: request)
    }

    public func openSFTP() async throws -> SFTPClient {
        guard let connection else { throw HostpaneSSHError.notConnected }
        return try await connection.openSFTP()
    }

    public func close() async {
        await connection?.close()
        connection = nil
        agent = nil
    }

    private func makeConfiguration(
        host: HostRecord,
        secrets: SecretStore,
        overrides: SSHSecretOverrides,
        settings: AppSettings,
        keepAlive: SSHKeepAliveMode
    ) async throws -> SSHClientConfiguration {
        let host = sshConfig.resolved(host)
        guard host.sshPort >= 1 else { throw HostpaneSSHError.invalidPort }
        let methods = try await authenticationMethods(for: host, secrets: secrets, overrides: overrides)
        guard !methods.isEmpty else { throw HostpaneSSHError.noAuthenticationMethods }
        let timeout = TimeInterval(AppSettings.clampedSeconds(settings.connectionTimeoutSeconds))
        let keepAliveSeconds: Int
        switch keepAlive {
        case .terminal:
            keepAliveSeconds = settings.terminalKeepAlive
                ? settings.terminalKeepAliveSeconds
                : Int(SSHKeepalivePolicy.defaultInterval)
        case .sftp, .docker:
            keepAliveSeconds = settings.sftpKeepAlive
                ? settings.sftpKeepAliveSeconds
                : Int(SSHKeepalivePolicy.defaultInterval)
        }
        return SSHClientConfiguration(
            host: host.hostname,
            port: host.sshPort,
            username: host.username,
            authenticationMethods: methods,
            hostKeyPolicy: settings.alwaysTrustHostKeys
                ? .acceptAnyVerifiedHostKey
                : .trustOnFirstUse(using: hostKeyStore),
            keepalivePolicy: SSHKeepalivePolicy(
                interval: TimeInterval(AppSettings.clampedSeconds(keepAliveSeconds))
            ),
            timeoutPolicy: SSHTimeoutPolicy(connectionSetupTimeInterval: timeout)
        )
    }

    private func authenticationMethods(
        for host: HostRecord,
        secrets: SecretStore,
        overrides: SSHSecretOverrides
    ) async throws -> [SSHAuthenticationMethod] {
        var methods: [SSHAuthenticationMethod] = []

        switch host.authKind {
        case .agent:
            methods.append(contentsOf: await agentMethods(preferredFingerprint: host.sshKeyFingerprint))
            methods.append(contentsOf: defaultKeyMethods(passphrase: nil))
        case .privateKey:
            guard let path = host.privateKeyPath, FileManager.default.isReadableFile(atPath: path) else {
                throw HostpaneSSHError.missingPrivateKey
            }
            let storedPassphrase = try secrets.get(account: secrets.passphraseAccount(for: host.id))
            let passphrase = nonEmpty(overrides.passphrase) ?? storedPassphrase
            methods.append(try SSHAuthenticationMethod.privateKeyPEM(contentsOfFile: path, passphrase: passphrase))
            methods.append(contentsOf: await agentMethods(preferredFingerprint: host.sshKeyFingerprint))
        case .password:
            let storedPassword = try secrets.get(account: secrets.passwordAccount(for: host.id))
            guard let password = nonEmpty(overrides.password) ?? nonEmpty(storedPassword) else {
                throw HostpaneSSHError.missingPassword
            }
            methods.append(.password(password))
        }

        return methods
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func agentMethods(preferredFingerprint: String? = nil) async -> [SSHAuthenticationMethod] {
        for path in SSHAgentSockets.available() {
            do {
                let client = try SSHAgentClient(socketPath: path)
                var identities = try await client.identities()
                guard !identities.isEmpty else { continue }
                if let preferredFingerprint, !preferredFingerprint.isEmpty {
                    identities.sort { lhs, rhs in
                        let left = SSHKeyFile.fingerprint(of: Data(lhs.publicKey)) == preferredFingerprint
                        let right = SSHKeyFile.fingerprint(of: Data(rhs.publicKey)) == preferredFingerprint
                        return left && !right
                    }
                }
                agent = client
                return identities.map { client.authenticationMethod(for: $0) }
            } catch {
                continue
            }
        }
        return []
    }

    private func defaultKeyMethods(passphrase: String?) -> [SSHAuthenticationMethod] {
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        let candidates = ["id_ed25519", "id_ecdsa", "id_rsa"].map { home.appendingPathComponent($0).path }
        var methods: [SSHAuthenticationMethod] = []
        for path in candidates where FileManager.default.isReadableFile(atPath: path) {
            if let method = try? SSHAuthenticationMethod.privateKeyPEM(contentsOfFile: path, passphrase: passphrase) {
                methods.append(method)
            }
        }
        return methods
    }

}

public func describeSSHError(_ error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    if let clientError = error as? SSHClientError {
        switch clientError {
        case .connectionFailed(let failure):
            return failure.message
        case .authenticationRejected(let methodName, _, _, _):
            return "认证失败（\(methodName)）。"
        default:
            return String(describing: clientError)
        }
    }
    return error.localizedDescription
}
