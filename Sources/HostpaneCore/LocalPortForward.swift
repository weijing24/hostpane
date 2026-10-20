import Foundation
import Traversio

public struct LocalForwardSpec: Equatable, Sendable {
    public var localHost: String
    public var localPort: UInt16
    public var targetHost: String
    public var targetPort: UInt16

    public init(localHost: String, localPort: UInt16, targetHost: String, targetPort: UInt16) {
        self.localHost = localHost
        self.localPort = localPort
        self.targetHost = targetHost
        self.targetPort = targetPort
    }
}

public struct LocalForwardBinding: Equatable, Sendable {
    public var localHost: String
    public var localPort: UInt16
    public var targetHost: String
    public var targetPort: UInt16

    public init(localHost: String, localPort: UInt16, targetHost: String, targetPort: UInt16) {
        self.localHost = localHost
        self.localPort = localPort
        self.targetHost = targetHost
        self.targetPort = targetPort
    }
}

/// NAS ports Hostpane listens for when suggested local forwarding is on.
public enum SuggestedLocalForwards {
    public static let ports: [UInt16] = [8080, 3622, 8090]

    public static func matches(_ host: HostRecord) -> Bool {
        let name = host.name.lowercased()
        let hostname = host.hostname.lowercased()
        return name.contains("synology") || hostname.contains("synology")
    }

    public static func specs() -> [LocalForwardSpec] {
        ports.map { port in
            LocalForwardSpec(
                localHost: "127.0.0.1",
                localPort: port,
                targetHost: "127.0.0.1",
                targetPort: port
            )
        }
    }
}

/// Authentication and local configuration errors should stop. A dead transport can be tried again.
public func localForwardConnectShouldRetry(_ error: Error) -> Bool {
    if error is HostpaneSSHError || error is CancellationError { return false }
    guard let client = error as? SSHClientError else { return true }
    switch client {
    case .authenticationRejected, .passwordChangeRequired:
        return false
    case .connectionFailed, .operationFailed, .connectionScopeEnded:
        return true
    }
}

public func localForwardRetryProbes() -> Bool {
    let auth = SSHClientError.authenticationRejected(
        methodName: "publickey",
        availableMethods: [],
        partialSuccess: false
    )
    return !localForwardConnectShouldRetry(auth)
        && !localForwardConnectShouldRetry(HostpaneSSHError.missingPassword)
        && !localForwardConnectShouldRetry(CancellationError())
        && localForwardConnectShouldRetry(SSHClientError.connectionScopeEnded)
}
