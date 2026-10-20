import Foundation

public enum SnippetEngineChoice: String, Sendable, Equatable {
    case monitor
    case terminal
    case fresh
}

public enum SnippetExecutionPlan {
    public static let maxConcurrentHosts = 4

    /// Prefer a connection this host already has. A new SSH session is the fallback.
    public static func engineChoice(monitorConnected: Bool, terminalConnected: Bool) -> SnippetEngineChoice {
        if monitorConnected { return .monitor }
        if terminalConnected { return .terminal }
        return .fresh
    }
}
