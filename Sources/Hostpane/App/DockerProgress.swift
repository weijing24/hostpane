import Foundation
import HostpaneCore
import Traversio

enum DockerConnectStep: String, CaseIterable, Identifiable {
    case connect
    case detect
    case load
    case ready

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connect: return "连接"
        case .detect: return "检测引擎"
        case .load: return "加载数据"
        case .ready: return "就绪"
        }
    }
}

enum DockerEventFilter: String, CaseIterable, Identifiable {
    case all
    case container
    case image
    case volume
    case network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .container: return "容器"
        case .image: return "镜像"
        case .volume: return "卷"
        case .network: return "网络"
        }
    }
}

enum DockerContainerFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case stopped
    case paused

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .running: return "运行中"
        case .stopped: return "已停止"
        case .paused: return "已暂停"
        }
    }
}

enum DockerContainerSort: String, CaseIterable, Identifiable {
    case name
    case status
    case cpu
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "名称"
        case .status: return "状态"
        case .cpu: return "CPU"
        case .memory: return "内存"
        }
    }
}

enum DockerTab: String, CaseIterable, Identifiable, Hashable {
    case overview
    case containers
    case compose
    case images
    case volumes
    case networks
    case events

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .containers: return "容器"
        case .compose: return "Compose"
        case .images: return "镜像"
        case .volumes: return "卷"
        case .networks: return "网络"
        case .events: return "事件"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "chart.bar.doc.horizontal"
        case .containers: return "shippingbox"
        case .compose: return "square.stack.3d.up"
        case .images: return "internaldrive"
        case .volumes: return "externaldrive"
        case .networks: return "network"
        case .events: return "bell"
        }
    }
}

@MainActor
@Observable
final class DockerConnectionProgress {
    var steps: [DockerConnectStep: ConnectStepState] = [
        .connect: .pending,
        .detect: .pending,
        .load: .pending,
        .ready: .pending
    ]
    var logs: [ConnectionLogLine] = []
    var logsVisible = true
    var cardVisible = true

    func reset() {
        steps = [
            .connect: .running,
            .detect: .pending,
            .load: .pending,
            .ready: .pending
        ]
        logs = []
        logsVisible = true
        cardVisible = true
    }

    func appendSetup(host: HostRecord) {
        append(
            category: "setup",
            message: "Setting up Docker panel with \(host.hostname):\(host.port)"
        )
        mark(.connect, .running)
    }

    func appendDetect(engine: DockerEngineInfo) {
        append(category: "diagnostics", message: "Detecting Docker engine")
        append(
            category: "diagnostics",
            message: "Resolving Docker context, host, sockets, and CLI availability"
        )
        append(category: "diagnostics", message: "Current Docker context is \(engine.context)")
        if !engine.socket.isEmpty {
            let endpoint = engine.socket.hasPrefix("unix://") ? engine.socket : "unix://\(engine.socket)"
            append(category: "diagnostics", message: "Effective Docker endpoint is \(endpoint)")
            let access = engine.socketWritable ? "writable" : "not writable"
            append(category: "diagnostics", message: "Found socket \(engine.socket) (\(access))")
        }
        if !engine.cliPath.isEmpty {
            append(category: "diagnostics", message: "docker CLI available at \(engine.cliPath)")
        }
        if !engine.version.isEmpty {
            append(category: "diagnostics", message: "Docker engine \(engine.version)")
        }
    }

    func appendLoad() {
        append(category: "diagnostics", message: "Loading Docker inventory")
    }

    func append(category: String, message: String, level: String = "INFO") {
        logs.append(
            ConnectionLogLine(
                timestamp: Date(),
                level: level,
                category: category,
                message: message,
                formattedLine: Self.format(Date(), level, Self.title(category), message)
            )
        )
    }

    func ingest(_ event: SSHClientLogEvent) {
        logs.append(ConnectionLogLine(event: event))
        let text = event.message.lowercased()
        if event.category == .transport || event.category == .connection {
            if text.contains("established") || text.contains("connected") || text.contains("ready") {
                if steps[.connect] == .running {
                    mark(.connect, .done)
                }
            }
        }
        if event.level == .error {
            failRemaining()
        }
    }

    func mark(_ step: DockerConnectStep, _ state: ConnectStepState) {
        steps[step] = state
        if state == .done {
            if let next = DockerConnectStep.allCases.drop(while: { $0 != step }).dropFirst().first,
               steps[next] == .pending {
                steps[next] = .running
            }
        }
        if state == .failed {
            for item in DockerConnectStep.allCases where steps[item] == .running {
                steps[item] = .failed
            }
        }
    }

    func failRemaining() {
        for step in DockerConnectStep.allCases where steps[step] == .running {
            steps[step] = .failed
        }
    }

    private static func title(_ category: String) -> String {
        switch category {
        case "diagnostics": return "Diagnostics"
        case "transport": return "Transport"
        case "setup": return "Setup"
        default: return category.capitalized
        }
    }

    private static func format(_ date: Date, _ level: String, _ category: String, _ message: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return "[\(formatter.string(from: date))] [\(level)] [\(category)] \(message)"
    }
}
