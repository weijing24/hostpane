import Foundation

public struct DiskSample: Equatable, Sendable, Identifiable {
    public var filesystem: String
    public var fstype: String
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var mount: String
    public var readBytes: UInt64
    public var writeBytes: UInt64
    public var readBytesPerSecond: Double?
    public var writeBytesPerSecond: Double?
    public var readIOPS: Double?
    public var writeIOPS: Double?
    public var readLatencyMs: Double?
    public var writeLatencyMs: Double?

    public var id: String { mount }

    public var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    /// Local block filesystems that represent machine storage, not network or pseudo mounts.
    public var isLocalStorage: Bool {
        let type = fstype.lowercased()
        if type.isEmpty { return true }
        let skip: Set<String> = [
            "tmpfs", "devtmpfs", "ramfs", "overlay", "squashfs", "aufs",
            "proc", "sysfs", "cgroup", "cgroup2", "devpts", "autofs",
            "nfs", "nfs4", "cifs", "smb", "smbfs", "afs", "afp", "9p",
            "ceph", "glusterfs", "gpfs", "lustre", "fuse", "iso9660", "udf"
        ]
        if skip.contains(type) { return false }
        if type.hasPrefix("nfs") { return false }
        if type.hasPrefix("fuse.ssh") || type.hasPrefix("fuse.rclone") || type.hasPrefix("fuse.s3") {
            return false
        }
        return true
    }

    public var hasIOStats: Bool {
        readBytes > 0 || writeBytes > 0
            || readBytesPerSecond != nil || writeBytesPerSecond != nil
    }

    public init(
        filesystem: String,
        fstype: String = "",
        totalBytes: UInt64,
        usedBytes: UInt64,
        mount: String,
        readBytes: UInt64 = 0,
        writeBytes: UInt64 = 0,
        readBytesPerSecond: Double? = nil,
        writeBytesPerSecond: Double? = nil,
        readIOPS: Double? = nil,
        writeIOPS: Double? = nil,
        readLatencyMs: Double? = nil,
        writeLatencyMs: Double? = nil
    ) {
        self.filesystem = filesystem
        self.fstype = fstype
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.mount = mount
        self.readBytes = readBytes
        self.writeBytes = writeBytes
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
        self.readIOPS = readIOPS
        self.writeIOPS = writeIOPS
        self.readLatencyMs = readLatencyMs
        self.writeLatencyMs = writeLatencyMs
    }
}

public struct CPUTimes: Equatable, Sendable {
    public var user: Double
    public var nice: Double
    public var system: Double
    public var iowait: Double
    public var irq: Double
    public var steal: Double
    public var usage: Double

    public init(
        user: Double,
        nice: Double,
        system: Double,
        iowait: Double,
        irq: Double,
        steal: Double,
        usage: Double
    ) {
        self.user = user
        self.nice = nice
        self.system = system
        self.iowait = iowait
        self.irq = irq
        self.steal = steal
        self.usage = usage
    }
}

public struct CoreSample: Equatable, Sendable, Identifiable {
    public var index: Int
    public var usage: Double?

    public var id: Int { index }

    public init(index: Int, usage: Double?) {
        self.index = index
        self.usage = usage
    }
}

public struct InterfaceSample: Equatable, Sendable, Identifiable {
    public var name: String
    public var ipv4CIDR: String?
    public var receiveBytes: UInt64
    public var transmitBytes: UInt64
    public var receiveBytesPerSecond: Double?
    public var transmitBytesPerSecond: Double?

    public var id: String { name }

    public init(
        name: String,
        ipv4CIDR: String? = nil,
        receiveBytes: UInt64,
        transmitBytes: UInt64,
        receiveBytesPerSecond: Double? = nil,
        transmitBytesPerSecond: Double? = nil
    ) {
        self.name = name
        self.ipv4CIDR = ipv4CIDR
        self.receiveBytes = receiveBytes
        self.transmitBytes = transmitBytes
        self.receiveBytesPerSecond = receiveBytesPerSecond
        self.transmitBytesPerSecond = transmitBytesPerSecond
    }
}

public struct ProcessSample: Equatable, Sendable, Identifiable {
    public var pid: Int
    public var user: String
    public var command: String
    public var cpuPercent: Double
    public var memoryPercent: Double
    public var rssBytes: UInt64

    public var id: Int { pid }

    public init(
        pid: Int,
        user: String,
        command: String,
        cpuPercent: Double,
        memoryPercent: Double,
        rssBytes: UInt64
    ) {
        self.pid = pid
        self.user = user
        self.command = command
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.rssBytes = rssBytes
    }
}

public struct ContainerSample: Equatable, Sendable, Identifiable {
    public var name: String
    public var status: String
    public var cpuRatio: Double
    public var memoryRatio: Double
    public var memoryUsedBytes: UInt64
    public var memoryLimitBytes: UInt64
    public var netReceiveBytes: UInt64
    public var netTransmitBytes: UInt64
    public var netReceiveBytesPerSecond: Double?
    public var netTransmitBytesPerSecond: Double?
    public var blockReadBytes: UInt64
    public var blockWriteBytes: UInt64
    public var blockReadBytesPerSecond: Double?
    public var blockWriteBytesPerSecond: Double?

    public var id: String { name }

    public init(
        name: String,
        status: String,
        cpuRatio: Double,
        memoryRatio: Double,
        memoryUsedBytes: UInt64,
        memoryLimitBytes: UInt64,
        netReceiveBytes: UInt64,
        netTransmitBytes: UInt64,
        netReceiveBytesPerSecond: Double? = nil,
        netTransmitBytesPerSecond: Double? = nil,
        blockReadBytes: UInt64,
        blockWriteBytes: UInt64,
        blockReadBytesPerSecond: Double? = nil,
        blockWriteBytesPerSecond: Double? = nil
    ) {
        self.name = name
        self.status = status
        self.cpuRatio = cpuRatio
        self.memoryRatio = memoryRatio
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.netReceiveBytes = netReceiveBytes
        self.netTransmitBytes = netTransmitBytes
        self.netReceiveBytesPerSecond = netReceiveBytesPerSecond
        self.netTransmitBytesPerSecond = netTransmitBytesPerSecond
        self.blockReadBytes = blockReadBytes
        self.blockWriteBytes = blockWriteBytes
        self.blockReadBytesPerSecond = blockReadBytesPerSecond
        self.blockWriteBytesPerSecond = blockWriteBytesPerSecond
    }
}

public struct HostMetrics: Equatable, Sendable {
    public var hostname: String
    public var operatingSystem: String
    public var osPrettyName: String
    public var osID: String
    public var cpuModel: String
    public var uptimeSeconds: Int
    public var loadAverage: (Double, Double, Double)?
    public var cpuCores: Int
    public var cpuUsage: Double?
    public var cpuTimes: CPUTimes?
    public var cores: [CoreSample]
    public var memoryTotalBytes: UInt64
    public var memoryAvailableBytes: UInt64
    public var memoryFreeBytes: UInt64
    public var memoryCachedBytes: UInt64
    public var swapTotalBytes: UInt64
    public var swapFreeBytes: UInt64
    public var disks: [DiskSample]
    public var interfaces: [InterfaceSample]
    public var netReceiveBytesPerSecond: Double?
    public var netTransmitBytesPerSecond: Double?
    public var diskReadBytesPerSecond: Double?
    public var diskWriteBytesPerSecond: Double?
    public var processes: [ProcessSample]
    public var containers: [ContainerSample]
    public var dockerEngineVersion: String
    public var dockerImageCount: Int
    public var dockerRunningCount: Int
    public var dockerStoppedCount: Int
    public var sshLatencySeconds: Double?
    public var sampledAt: Date

    public var hasDockerEngine: Bool {
        !dockerEngineVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var memoryUsedBytes: UInt64 {
        memoryTotalBytes > memoryAvailableBytes ? memoryTotalBytes - memoryAvailableBytes : 0
    }

    public var memoryUsedRatio: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return Double(memoryUsedBytes) / Double(memoryTotalBytes)
    }

    public var memoryBreakdownUsedBytes: UInt64 {
        let remainder = memoryTotalBytes.subtractingReportingOverflow(memoryFreeBytes &+ memoryCachedBytes)
        if remainder.overflow { return memoryUsedBytes }
        return remainder.partialValue
    }

    public var swapUsedBytes: UInt64 {
        swapTotalBytes > swapFreeBytes ? swapTotalBytes - swapFreeBytes : 0
    }

    public var swapUsedRatio: Double {
        guard swapTotalBytes > 0 else { return 0 }
        return Double(swapUsedBytes) / Double(swapTotalBytes)
    }

    public var osDisplayName: String {
        let pretty = osPrettyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return pretty.isEmpty ? operatingSystem : pretty
    }

    public var primaryInterface: InterfaceSample? {
        interfaces.max {
            ($0.receiveBytes &+ $0.transmitBytes) < ($1.receiveBytes &+ $1.transmitBytes)
        }
    }

    public func preferredInterface(named: String?) -> InterfaceSample? {
        let needle = named?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !needle.isEmpty, let match = interfaces.first(where: { $0.name == needle }) {
            return match
        }
        return primaryInterface
    }

    public func preferredDisk(mount: String?) -> DiskSample? {
        let needle = mount?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !needle.isEmpty, let match = localDisks.first(where: { $0.mount == needle }) {
            return match
        }
        return primaryDisk
    }

    public var localDisks: [DiskSample] {
        disks.filter(\.isLocalStorage)
    }

    /// Largest local volume. Synology and similar NAS hosts keep a tiny `/` and the real pool on `/volume1`.
    public var primaryDisk: DiskSample? {
        localDisks.max { lhs, rhs in
            if lhs.totalBytes != rhs.totalBytes {
                return lhs.totalBytes < rhs.totalBytes
            }
            return lhs.mount != "/" && rhs.mount == "/"
        }
    }

    public var localStorageBytes: UInt64 {
        uniqueLocalDisks.reduce(into: UInt64(0)) { $0 &+= $1.totalBytes }
    }

    public var localStorageUsedBytes: UInt64 {
        uniqueLocalDisks.reduce(into: UInt64(0)) { $0 &+= $1.usedBytes }
    }

    /// One row per block device so btrfs/zfs subvolumes of the same device are not summed twice.
    private var uniqueLocalDisks: [DiskSample] {
        var best: [String: DiskSample] = [:]
        for disk in localDisks {
            let key = disk.filesystem.isEmpty ? "mount:\(disk.mount)" : disk.filesystem
            if let existing = best[key], existing.totalBytes >= disk.totalBytes {
                continue
            }
            best[key] = disk
        }
        return Array(best.values)
    }

    public var isLinux: Bool {
        operatingSystem.lowercased().hasPrefix("linux")
    }

    public init(
        hostname: String,
        operatingSystem: String,
        osPrettyName: String = "",
        osID: String = "",
        cpuModel: String = "",
        uptimeSeconds: Int,
        loadAverage: (Double, Double, Double)?,
        cpuCores: Int = 0,
        cpuUsage: Double?,
        cpuTimes: CPUTimes? = nil,
        cores: [CoreSample] = [],
        memoryTotalBytes: UInt64,
        memoryAvailableBytes: UInt64,
        memoryFreeBytes: UInt64 = 0,
        memoryCachedBytes: UInt64 = 0,
        swapTotalBytes: UInt64,
        swapFreeBytes: UInt64,
        disks: [DiskSample],
        interfaces: [InterfaceSample] = [],
        netReceiveBytesPerSecond: Double?,
        netTransmitBytesPerSecond: Double?,
        diskReadBytesPerSecond: Double? = nil,
        diskWriteBytesPerSecond: Double? = nil,
        processes: [ProcessSample] = [],
        containers: [ContainerSample] = [],
        dockerEngineVersion: String = "",
        dockerImageCount: Int = 0,
        dockerRunningCount: Int = 0,
        dockerStoppedCount: Int = 0,
        sshLatencySeconds: Double? = nil,
        sampledAt: Date
    ) {
        self.hostname = hostname
        self.operatingSystem = operatingSystem
        self.osPrettyName = osPrettyName
        self.osID = osID
        self.cpuModel = cpuModel
        self.uptimeSeconds = uptimeSeconds
        self.loadAverage = loadAverage
        self.cpuCores = cpuCores
        self.cpuUsage = cpuUsage
        self.cpuTimes = cpuTimes
        self.cores = cores
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryAvailableBytes = memoryAvailableBytes
        self.memoryFreeBytes = memoryFreeBytes
        self.memoryCachedBytes = memoryCachedBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapFreeBytes = swapFreeBytes
        self.disks = disks
        self.interfaces = interfaces
        self.netReceiveBytesPerSecond = netReceiveBytesPerSecond
        self.netTransmitBytesPerSecond = netTransmitBytesPerSecond
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
        self.processes = processes
        self.containers = containers
        self.dockerEngineVersion = dockerEngineVersion
        self.dockerImageCount = dockerImageCount
        self.dockerRunningCount = dockerRunningCount
        self.dockerStoppedCount = dockerStoppedCount
        self.sshLatencySeconds = sshLatencySeconds
        self.sampledAt = sampledAt
    }
}

extension HostMetrics {
    public static func == (lhs: HostMetrics, rhs: HostMetrics) -> Bool {
        lhs.hostname == rhs.hostname
            && lhs.operatingSystem == rhs.operatingSystem
            && lhs.osPrettyName == rhs.osPrettyName
            && lhs.osID == rhs.osID
            && lhs.cpuModel == rhs.cpuModel
            && lhs.uptimeSeconds == rhs.uptimeSeconds
            && lhs.loadAverage.map { [$0.0, $0.1, $0.2] } == rhs.loadAverage.map { [$0.0, $0.1, $0.2] }
            && lhs.cpuCores == rhs.cpuCores
            && lhs.cpuUsage == rhs.cpuUsage
            && lhs.cpuTimes == rhs.cpuTimes
            && lhs.cores == rhs.cores
            && lhs.memoryTotalBytes == rhs.memoryTotalBytes
            && lhs.memoryAvailableBytes == rhs.memoryAvailableBytes
            && lhs.memoryFreeBytes == rhs.memoryFreeBytes
            && lhs.memoryCachedBytes == rhs.memoryCachedBytes
            && lhs.swapTotalBytes == rhs.swapTotalBytes
            && lhs.swapFreeBytes == rhs.swapFreeBytes
            && lhs.disks == rhs.disks
            && lhs.interfaces == rhs.interfaces
            && lhs.netReceiveBytesPerSecond == rhs.netReceiveBytesPerSecond
            && lhs.netTransmitBytesPerSecond == rhs.netTransmitBytesPerSecond
            && lhs.diskReadBytesPerSecond == rhs.diskReadBytesPerSecond
            && lhs.diskWriteBytesPerSecond == rhs.diskWriteBytesPerSecond
            && lhs.processes == rhs.processes
            && lhs.containers == rhs.containers
            && lhs.dockerEngineVersion == rhs.dockerEngineVersion
            && lhs.dockerImageCount == rhs.dockerImageCount
            && lhs.dockerRunningCount == rhs.dockerRunningCount
            && lhs.dockerStoppedCount == rhs.dockerStoppedCount
            && lhs.sshLatencySeconds == rhs.sshLatencySeconds
            && lhs.sampledAt == rhs.sampledAt
    }
}

public func parseDataSize(_ raw: String) -> UInt64? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    var number = ""
    var unit = ""
    var seenDot = false
    for character in trimmed {
        if character.isNumber {
            number.append(character)
        } else if character == ".", !seenDot {
            number.append(character)
            seenDot = true
        } else if !character.isWhitespace {
            unit.append(character)
        }
    }
    guard let value = Double(number), value >= 0 else { return nil }
    let factor: Double
    switch unit.lowercased() {
    case "", "b":
        factor = 1
    case "k", "kb":
        factor = 1_000
    case "kib":
        factor = 1_024
    case "m", "mb":
        factor = 1_000_000
    case "mib":
        factor = 1_024 * 1_024
    case "g", "gb":
        factor = 1_000_000_000
    case "gib":
        factor = 1_024 * 1_024 * 1_024
    case "t", "tb":
        factor = 1_000_000_000_000
    case "tib":
        factor = 1_024 * 1_024 * 1_024 * 1_024
    default:
        return nil
    }
    return UInt64(value * factor)
}

public func parsePercentRatio(_ raw: String) -> Double {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")
    guard let value = Double(trimmed) else { return 0 }
    return min(max(value / 100, 0), 1)
}
