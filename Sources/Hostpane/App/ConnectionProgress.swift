import Foundation
import HostpaneCore
import Traversio

enum ConnectStep: String, CaseIterable, Identifiable {
    case network
    case handshake
    case authentication
    case shell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .network: return "网络"
        case .handshake: return "握手"
        case .authentication: return "认证"
        case .shell: return "Shell"
        }
    }

    var systemImage: String {
        switch self {
        case .network: return "network"
        case .handshake: return "checkmark.shield"
        case .authentication: return "person.crop.circle.badge.checkmark"
        case .shell: return "terminal"
        }
    }
}

enum ConnectStepState: Equatable {
    case pending
    case running
    case done
    case failed
}

struct ConnectionLogLine: Identifiable, Equatable {
    var id = UUID()
    var timestamp: Date
    var level: String
    var category: String
    var message: String
    var formattedLine: String

    init(
        id: UUID = UUID(),
        timestamp: Date,
        level: String,
        category: String,
        message: String,
        formattedLine: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.formattedLine = formattedLine
    }

    init(event: SSHClientLogEvent) {
        let level: String
        switch event.level {
        case .debug: level = "DEBUG"
        case .info: level = "INFO"
        case .notice: level = "NOTICE"
        case .warning: level = "WARN"
        case .error: level = "ERROR"
        }
        let category: String
        switch event.category {
        case .transport: category = "transport"
        case .connection: category = "connection"
        case .authentication: category = "authentication"
        case .session: category = "session"
        case .sftp: category = "sftp"
        case .forwarding: category = "forwarding"
        }
        self.init(
            timestamp: event.timestamp,
            level: level,
            category: category,
            message: event.message,
            formattedLine: event.formattedLine
        )
    }

    var sectionTitle: String {
        switch category {
        case "transport", "connection": return "传输"
        case "authentication": return "认证"
        case "session": return "会话"
        case "diagnostics": return "诊断"
        default: return "设置"
        }
    }
}

@MainActor
@Observable
final class ConnectionProgress {
    var steps: [ConnectStep: ConnectStepState] = [
        .network: .pending,
        .handshake: .pending,
        .authentication: .pending,
        .shell: .pending
    ]
    var logs: [ConnectionLogLine] = []
    var logsVisible = true
    var cardVisible = true

    func reset() {
        steps = [
            .network: .running,
            .handshake: .pending,
            .authentication: .pending,
            .shell: .pending
        ]
        logs = []
        logsVisible = true
        cardVisible = true
    }

    func appendSetup(host: HostRecord) {
        let message = "Setting up new SSH terminal with \(host.displayName), \(host.username)@\(host.hostname):\(host.port) transport=ssh"
        logs.append(
            ConnectionLogLine(
                timestamp: Date(),
                level: "INFO",
                category: "setup",
                message: message,
                formattedLine: Self.format(Date(), "INFO", "Setup", message)
            )
        )
        mark(.network, .running)
    }

    func ingest(_ event: SSHClientLogEvent) {
        logs.append(
            ConnectionLogLine(
                timestamp: event.timestamp,
                level: Self.levelName(event.level),
                category: Self.categoryName(event.category),
                message: event.message,
                formattedLine: event.formattedLine
            )
        )
        advance(using: event)
    }

    func mark(_ step: ConnectStep, _ state: ConnectStepState) {
        steps[step] = state
        if state == .done {
            if let next = ConnectStep.allCases.drop(while: { $0 != step }).dropFirst().first,
               steps[next] == .pending {
                steps[next] = .running
            }
        }
        if state == .failed {
            for item in ConnectStep.allCases where steps[item] == .running {
                steps[item] = .failed
            }
        }
    }

    func failRemaining() {
        for step in ConnectStep.allCases {
            if steps[step] == .running || steps[step] == .pending {
                if steps[step] == .running {
                    steps[step] = .failed
                }
            }
        }
    }

    private func advance(using event: SSHClientLogEvent) {
        let text = event.message.lowercased()
        switch event.category {
        case .transport, .connection:
            if steps[.network] == .running {
                if text.contains("ready") || text.contains("connected") || text.contains("established") {
                    mark(.network, .done)
                }
            }
            if steps[.handshake] == .running || steps[.network] == .done {
                if text.contains("kex") || text.contains("handshake") || text.contains("identification") {
                    if steps[.handshake] != .done { steps[.handshake] = .running }
                }
                if text.contains("hostkey") || text.contains("host key") || text.contains("algorithm") {
                    mark(.handshake, .done)
                }
            }
        case .authentication:
            if steps[.handshake] != .done { mark(.handshake, .done) }
            if steps[.authentication] != .done {
                steps[.authentication] = .running
            }
            if text.contains("succeed") || text.contains("established") {
                mark(.authentication, .done)
            }
            if event.level == .error || text.contains("fail") || text.contains("reject") {
                mark(.authentication, .failed)
            }
        case .session:
            if steps[.authentication] != .done { mark(.authentication, .done) }
            if steps[.shell] != .done { steps[.shell] = .running }
        default:
            break
        }
        if event.level == .error {
            failRemaining()
        }
    }

    private static func levelName(_ level: SSHClientLogLevel) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }

    private static func categoryName(_ category: SSHClientLogCategory) -> String {
        switch category {
        case .transport: return "transport"
        case .connection: return "connection"
        case .authentication: return "authentication"
        case .session: return "session"
        case .sftp: return "sftp"
        case .forwarding: return "forwarding"
        }
    }

    private static func format(_ date: Date, _ level: String, _ category: String, _ message: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return "[\(formatter.string(from: date))] [\(level)] [\(category)] \(message)"
    }
}
