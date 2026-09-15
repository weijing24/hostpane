import Foundation

public struct DockerEngineInfo: Equatable, Sendable {
    public var version: String
    public var apiVersion: String
    public var os: String
    public var arch: String
    public var socket: String
    public var context: String
    public var cliPath: String
    public var socketWritable: Bool

    public init(
        version: String = "",
        apiVersion: String = "",
        os: String = "",
        arch: String = "",
        socket: String = "",
        context: String = "default",
        cliPath: String = "",
        socketWritable: Bool = false
    ) {
        self.version = version
        self.apiVersion = apiVersion
        self.os = os
        self.arch = arch
        self.socket = socket
        self.context = context
        self.cliPath = cliPath
        self.socketWritable = socketWritable
    }

    public var platformLine: String {
        let osPart = os.trimmingCharacters(in: .whitespacesAndNewlines)
        let archPart = arch.trimmingCharacters(in: .whitespacesAndNewlines)
        if osPart.isEmpty { return archPart }
        if archPart.isEmpty { return osPart }
        return "\(osPart) · \(archPart)"
    }

    public var hasEngine: Bool {
        !version.isEmpty || !cliPath.isEmpty
    }
}

public struct DockerDiskSlice: Equatable, Sendable {
    public var count: Int
    public var active: Int
    public var sizeBytes: UInt64
    public var reclaimableBytes: UInt64
    public var reclaimablePercent: Double?

    public init(
        count: Int = 0,
        active: Int = 0,
        sizeBytes: UInt64 = 0,
        reclaimableBytes: UInt64 = 0,
        reclaimablePercent: Double? = nil
    ) {
        self.count = count
        self.active = active
        self.sizeBytes = sizeBytes
        self.reclaimableBytes = reclaimableBytes
        self.reclaimablePercent = reclaimablePercent
    }
}

public struct DockerDiskUsage: Equatable, Sendable {
    public var images: DockerDiskSlice
    public var containers: DockerDiskSlice
    public var volumes: DockerDiskSlice
    public var buildCache: DockerDiskSlice

    public init(
        images: DockerDiskSlice = DockerDiskSlice(),
        containers: DockerDiskSlice = DockerDiskSlice(),
        volumes: DockerDiskSlice = DockerDiskSlice(),
        buildCache: DockerDiskSlice = DockerDiskSlice()
    ) {
        self.images = images
        self.containers = containers
        self.volumes = volumes
        self.buildCache = buildCache
    }

    public var totalBytes: UInt64 {
        images.sizeBytes &+ containers.sizeBytes &+ volumes.sizeBytes &+ buildCache.sizeBytes
    }

    public var reclaimableBytes: UInt64 {
        images.reclaimableBytes &+ containers.reclaimableBytes &+ volumes.reclaimableBytes &+ buildCache.reclaimableBytes
    }

    public var reclaimableShare: Double? {
        guard totalBytes > 0 else { return nil }
        return Double(reclaimableBytes) / Double(totalBytes)
    }
}

public struct DockerMount: Equatable, Sendable, Identifiable {
    public var source: String
    public var destination: String
    public var readOnly: Bool
    public var type: String

    public var id: String { "\(source)>\(destination)" }

    public init(source: String, destination: String, readOnly: Bool, type: String) {
        self.source = source
        self.destination = destination
        self.readOnly = readOnly
        self.type = type
    }
}

public struct DockerStatPoint: Equatable, Sendable {
    public var at: Date
    public var cpuRatio: Double
    public var memoryRatio: Double
    public var memoryUsedBytes: UInt64

    public init(at: Date, cpuRatio: Double, memoryRatio: Double, memoryUsedBytes: UInt64) {
        self.at = at
        self.cpuRatio = cpuRatio
        self.memoryRatio = memoryRatio
        self.memoryUsedBytes = memoryUsedBytes
    }
}

public struct DockerContainer: Equatable, Sendable, Identifiable {
    public var containerID: String
    public var name: String
    public var image: String
    public var state: String
    public var status: String
    public var ports: String
    public var cpuRatio: Double
    public var memoryRatio: Double
    public var memoryUsedBytes: UInt64
    public var memoryLimitBytes: UInt64
    public var netReceiveBytes: UInt64
    public var netTransmitBytes: UInt64
    public var blockReadBytes: UInt64
    public var blockWriteBytes: UInt64
    public var health: String
    public var created: String
    public var command: String
    public var restartPolicy: String
    public var composeProject: String
    public var composeService: String
    public var networkMode: String
    public var pid: Int
    public var mounts: [DockerMount]
    public var env: [String]
    public var volumeNames: [String]
    public var networkNames: [String]

    public var id: String { name.isEmpty ? containerID : name }

    public var shortID: String {
        let trimmed = containerID.hasPrefix("sha256:") ? String(containerID.dropFirst(7)) : containerID
        return String(trimmed.prefix(12))
    }

    public var isRunning: Bool { state.lowercased() == "running" }
    public var isPaused: Bool { state.lowercased() == "paused" }
    public var isStopped: Bool {
        let value = state.lowercased()
        return value == "exited" || value == "dead" || value == "created"
    }

    public var isHealthy: Bool { health.lowercased() == "healthy" }

    public var composeLine: String {
        if composeProject.isEmpty { return "" }
        if composeService.isEmpty { return composeProject }
        return "\(composeProject) · \(composeService)"
    }

    public init(
        containerID: String,
        name: String,
        image: String,
        state: String,
        status: String,
        ports: String = "",
        cpuRatio: Double = 0,
        memoryRatio: Double = 0,
        memoryUsedBytes: UInt64 = 0,
        memoryLimitBytes: UInt64 = 0,
        netReceiveBytes: UInt64 = 0,
        netTransmitBytes: UInt64 = 0,
        blockReadBytes: UInt64 = 0,
        blockWriteBytes: UInt64 = 0,
        health: String = "",
        created: String = "",
        command: String = "",
        restartPolicy: String = "",
        composeProject: String = "",
        composeService: String = "",
        networkMode: String = "",
        pid: Int = 0,
        mounts: [DockerMount] = [],
        env: [String] = [],
        volumeNames: [String] = [],
        networkNames: [String] = []
    ) {
        self.containerID = containerID
        self.name = name
        self.image = image
        self.state = state
        self.status = status
        self.ports = ports
        self.cpuRatio = cpuRatio
        self.memoryRatio = memoryRatio
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.netReceiveBytes = netReceiveBytes
        self.netTransmitBytes = netTransmitBytes
        self.blockReadBytes = blockReadBytes
        self.blockWriteBytes = blockWriteBytes
        self.health = health
        self.created = created
        self.command = command
        self.restartPolicy = restartPolicy
        self.composeProject = composeProject
        self.composeService = composeService
        self.networkMode = networkMode
        self.pid = pid
        self.mounts = mounts
        self.env = env
        self.volumeNames = volumeNames
        self.networkNames = networkNames
    }
}

public struct DockerImageLayer: Equatable, Sendable, Identifiable {
    public var createdBy: String
    public var sizeLabel: String
    public var id: String { "\(createdBy)|\(sizeLabel)" }

    public init(createdBy: String, sizeLabel: String) {
        self.createdBy = createdBy
        self.sizeLabel = sizeLabel
    }
}

public struct DockerImage: Equatable, Sendable, Identifiable {
    public var imageID: String
    public var repository: String
    public var tag: String
    public var sizeLabel: String
    public var created: String
    public var digest: String
    public var sharedSizeLabel: String
    public var createdAt: String
    public var repoTags: [String]
    public var layers: [DockerImageLayer]
    public var historyLoaded: Bool

    public var id: String { "\(shortID)|\(reference)" }

    public var shortID: String {
        let trimmed = imageID.hasPrefix("sha256:") ? String(imageID.dropFirst(7)) : imageID
        return String(trimmed.prefix(12))
    }

    public var isDangling: Bool {
        repository == "<none>" || tag == "<none>" || repository.isEmpty
    }

    public var displayName: String {
        if isDangling { return "<无>" }
        return reference
    }

    public var reference: String {
        if isDangling { return shortID }
        if tag.isEmpty { return repository }
        return "\(repository):\(tag)"
    }

    public var digestLine: String {
        if digest.isEmpty || digest == "<none>" { return "" }
        if digest.contains("@") { return digest }
        if isDangling { return digest }
        return "\(repository)@\(digest)"
    }

    public init(
        imageID: String,
        repository: String,
        tag: String,
        sizeLabel: String,
        created: String,
        digest: String = "",
        sharedSizeLabel: String = "",
        createdAt: String = "",
        repoTags: [String] = [],
        layers: [DockerImageLayer] = [],
        historyLoaded: Bool = false
    ) {
        self.imageID = imageID
        self.repository = repository
        self.tag = tag
        self.sizeLabel = sizeLabel
        self.created = created
        self.digest = digest
        self.sharedSizeLabel = sharedSizeLabel
        self.createdAt = createdAt
        self.repoTags = repoTags.isEmpty && !repository.isEmpty && tag != "<none>"
            ? ["\(repository):\(tag)"]
            : repoTags
        self.layers = layers
        self.historyLoaded = historyLoaded
    }

    public func usedBy(_ containers: [DockerContainer]) -> [DockerContainer] {
        containers.filter { uses(container: $0) }
    }

    public func uses(container: DockerContainer) -> Bool {
        let image = container.image
        if image == reference || image == "\(repository):\(tag)" { return true }
        if image.hasPrefix(shortID) || image.contains(shortID) { return true }
        if !digest.isEmpty, image.contains(digest) { return true }
        return false
    }
}

public struct DockerLabel: Equatable, Sendable, Identifiable {
    public var key: String
    public var value: String
    public var id: String { key }

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct DockerVolume: Equatable, Sendable, Identifiable {
    public var name: String
    public var driver: String
    public var mountpoint: String
    public var scope: String
    public var createdAt: String
    public var labels: [DockerLabel]
    public var inspectLoaded: Bool
    public var id: String { name }

    public init(
        name: String,
        driver: String,
        mountpoint: String,
        scope: String = "",
        createdAt: String = "",
        labels: [DockerLabel] = [],
        inspectLoaded: Bool = false
    ) {
        self.name = name
        self.driver = driver
        self.mountpoint = mountpoint
        self.scope = scope
        self.createdAt = createdAt
        self.labels = labels
        self.inspectLoaded = inspectLoaded
    }

    public func usedBy(_ containers: [DockerContainer]) -> [DockerContainer] {
        containers.filter { uses(container: $0) }
    }

    public func uses(container: DockerContainer) -> Bool {
        if container.volumeNames.contains(name) { return true }
        return container.mounts.contains { mount in
            mount.source.contains(name) || mount.destination.contains(name)
        }
    }
}

public struct DockerNetwork: Equatable, Sendable, Identifiable {
    public var networkID: String
    public var name: String
    public var driver: String
    public var scope: String
    public var subnet: String
    public var gateway: String
    public var inspectLoaded: Bool
    public var id: String { name }

    public var shortID: String {
        let trimmed = networkID.hasPrefix("sha256:") ? String(networkID.dropFirst(7)) : networkID
        return String(trimmed.prefix(12))
    }

    public var isBuiltin: Bool {
        ["bridge", "host", "none"].contains(name)
    }

    public init(
        networkID: String,
        name: String,
        driver: String,
        scope: String,
        subnet: String = "",
        gateway: String = "",
        inspectLoaded: Bool = false
    ) {
        self.networkID = networkID
        self.name = name
        self.driver = driver
        self.scope = scope
        self.subnet = subnet
        self.gateway = gateway
        self.inspectLoaded = inspectLoaded
    }

    public func usedBy(_ containers: [DockerContainer]) -> [DockerContainer] {
        containers.filter { uses(container: $0) }
    }

    public func uses(container: DockerContainer) -> Bool {
        if container.networkNames.contains(name) { return true }
        let mode = container.networkMode
        if mode == name { return true }
        if name == "bridge", mode.isEmpty || mode == "default" { return true }
        return false
    }
}

public struct DockerComposeProject: Equatable, Sendable, Identifiable {
    public var name: String
    public var status: String
    public var configFiles: String
    public var id: String { name }

    public init(name: String, status: String, configFiles: String) {
        self.name = name
        self.status = status
        self.configFiles = configFiles
    }
}

public struct DockerEvent: Equatable, Sendable, Identifiable {
    public var timestamp: String
    public var unixTime: TimeInterval
    public var type: String
    public var action: String
    public var actor: String
    public var image: String
    public var id: String { "\(timestamp)|\(type)|\(action)|\(actor)|\(image)" }

    public var title: String {
        let name = actor.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return action }
        if action == name || action.hasSuffix(" \(name)") || action.hasSuffix(":\(name)") {
            return action
        }
        return "\(action) \(name)"
    }

    public init(
        timestamp: String,
        unixTime: TimeInterval = 0,
        type: String,
        action: String,
        actor: String,
        image: String = ""
    ) {
        self.timestamp = timestamp
        self.unixTime = unixTime
        self.type = type
        self.action = action
        self.actor = actor
        self.image = image
    }
}

public struct DockerSnapshot: Equatable, Sendable {
    public var engine: DockerEngineInfo
    public var disk: DockerDiskUsage
    public var containers: [DockerContainer]
    public var images: [DockerImage]
    public var volumes: [DockerVolume]
    public var networks: [DockerNetwork]
    public var compose: [DockerComposeProject]
    public var events: [DockerEvent]
    public var sampledAt: Date

    public init(
        engine: DockerEngineInfo = DockerEngineInfo(),
        disk: DockerDiskUsage = DockerDiskUsage(),
        containers: [DockerContainer] = [],
        images: [DockerImage] = [],
        volumes: [DockerVolume] = [],
        networks: [DockerNetwork] = [],
        compose: [DockerComposeProject] = [],
        events: [DockerEvent] = [],
        sampledAt: Date = Date()
    ) {
        self.engine = engine
        self.disk = disk
        self.containers = containers
        self.images = images
        self.volumes = volumes
        self.networks = networks
        self.compose = compose
        self.events = events
        self.sampledAt = sampledAt
    }

    public var runningCount: Int { containers.filter(\.isRunning).count }
    public var pausedCount: Int { containers.filter(\.isPaused).count }
    public var stoppedCount: Int { containers.filter(\.isStopped).count }
    public var otherCount: Int {
        max(containers.count - runningCount - pausedCount - stoppedCount, 0)
    }

    public var totalCPURatio: Double {
        containers.reduce(0) { $0 + $1.cpuRatio }
    }

    public var totalMemoryBytes: UInt64 {
        containers.reduce(into: UInt64(0)) { $0 &+= $1.memoryUsedBytes }
    }

    public var topCPU: [DockerContainer] {
        Array(containers.sorted { $0.cpuRatio > $1.cpuRatio }.prefix(5))
    }

    public var topMemory: [DockerContainer] {
        Array(containers.sorted { $0.memoryUsedBytes > $1.memoryUsedBytes }.prefix(5))
    }

    public var danglingImageCount: Int {
        images.filter { $0.repository == "<none>" || $0.tag == "<none>" }.count
    }
}

public enum DockerProbeError: Error, LocalizedError {
    case missingCLI
    case engineUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .missingCLI:
            return "远程找不到 docker CLI。"
        case .engineUnavailable(let detail):
            return detail.isEmpty ? "无法连接到 Docker 引擎。" : detail
        }
    }
}
