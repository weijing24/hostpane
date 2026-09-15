import Foundation

public struct LinuxMetricsProbe {
    /// Tiny payload so dashboard latency is SSH round-trip, not probe runtime.
    public static let latencyCommand = "printf HP_PONG"

    public static let remoteCommand = #"""
    LANG=C LC_ALL=C
    echo HP_BEGIN
    echo "os=$(uname -s)"
    echo "hostname=$(hostname 2>/dev/null || uname -n)"
    os_pretty=""
    os_id=""
    if [ -r /etc/os-release ]; then
      os_pretty=$(awk -F= '/^PRETTY_NAME=/{v=$2; gsub(/"/,"",v); print v; exit}' /etc/os-release 2>/dev/null)
      os_id=$(awk -F= '/^ID=/{v=$2; gsub(/"/,"",v); print v; exit}' /etc/os-release 2>/dev/null)
    fi
    if [ -r /etc.defaults/VERSION ]; then
      product=$(awk -F= '/^productversion=/{v=$2; gsub(/"/,"",v); print v; exit}' /etc.defaults/VERSION 2>/dev/null)
      os_name=$(awk -F= '/^os_name=/{v=$2; gsub(/"/,"",v); print v; exit}' /etc.defaults/VERSION 2>/dev/null)
      if [ -n "$product" ]; then
        os_id=synology
        os_pretty="${os_name:-DSM} $product"
      fi
    fi
    echo "os_pretty=$os_pretty"
    echo "os_id=$os_id"
    if [ -r /proc/uptime ]; then
      echo "uptime_sec=$(cut -d. -f1 /proc/uptime)"
    else
      echo "uptime_sec=0"
    fi
    if [ -r /proc/loadavg ]; then
      echo "loadavg=$(cut -d' ' -f1-3 /proc/loadavg)"
    fi
    echo "cpu_cores=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0)"
    cpu_model=$(awk -F: '/^model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
    if [ -z "$cpu_model" ]; then
      cpu_model=$(awk -F: '/^Hardware/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
    fi
    if [ -z "$cpu_model" ]; then
      cpu_model=$(uname -m)
    fi
    echo "cpu_model=$cpu_model ($(uname -m))"
    echo "docker_engine=$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"
    echo "docker_images=$(docker images -q 2>/dev/null | wc -l | tr -d ' ')"
    echo "docker_running=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
    echo "docker_stopped=$(docker ps -aq -f status=exited 2>/dev/null | wc -l | tr -d ' ')"
    echo HP_STAT
    if [ -r /proc/stat ]; then
      grep '^cpu' /proc/stat
    fi
    echo HP_MEM
    if [ -r /proc/meminfo ]; then
      grep -E '^(MemTotal|MemAvailable|MemFree|Cached|Buffers|SReclaimable|SwapTotal|SwapFree):' /proc/meminfo
    fi
    echo HP_NET
    if [ -r /proc/net/dev ]; then
      cat /proc/net/dev
    fi
    echo HP_ADDR
    (ip -o -4 addr show || /sbin/ip -o -4 addr show || /usr/sbin/ip -o -4 addr show) 2>/dev/null || true
    echo HP_DISK
    if df -T -B1 -P >/dev/null 2>&1; then
      df -T -B1 -P -x tmpfs -x devtmpfs -x squashfs -x overlay -x udev 2>/dev/null || df -T -B1 -P
    elif df -B1 -P >/dev/null 2>&1; then
      df -B1 -P -x tmpfs -x devtmpfs -x squashfs -x overlay -x udev 2>/dev/null || df -B1 -P
    else
      df -P
    fi
    echo HP_DISKIO
    if [ -r /proc/diskstats ]; then
      cat /proc/diskstats
    fi
    echo HP_PROC
    ps -eo pid=,user:12=,pcpu=,pmem=,rss=,comm= --sort=-pcpu 2>/dev/null | head -n 80
    echo HP_DOCKER
    if command -v docker >/dev/null 2>&1; then
      docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}' 2>/dev/null | head -n 40
    fi
    echo HP_DOCKERPS
    if command -v docker >/dev/null 2>&1; then
      docker ps --format '{{.Names}}|{{.Status}}' 2>/dev/null | head -n 40
    fi
    echo HP_END
    """#

    public init() {}
}

public struct LinuxMetricsParser {
    private var lastCPU: CPUSnapshot?
    private var lastCores: [Int: CPUSnapshot] = [:]
    private var lastIfaces: [String: IfaceCounters] = [:]
    private var lastDiskDevices: [String: DeviceIOCounters] = [:]
    private var lastDocker: [String: DockerIO] = [:]
    private var lastSampleAt: Date?

    public init() {}

    public mutating func consume(_ text: String, at date: Date = Date()) throws -> HostMetrics {
        let sections = SectionMap(text: text)
        let os = sections.field("os") ?? "unknown"
        let osPrettyName = sections.field("os_pretty") ?? ""
        let osID = sections.field("os_id") ?? ""
        let hostname = sections.field("hostname") ?? "unknown"
        let uptime = Int(sections.field("uptime_sec") ?? "0") ?? 0
        let load = Self.parseLoadAverage(sections.field("loadavg"))
        let cpuCores = Int(sections.field("cpu_cores") ?? "0") ?? 0
        let cpuModel = sections.field("cpu_model") ?? ""

        let cpuStat = Self.parseCPUStat(sections.body("HP_STAT"))
        let ifaceCounters = Self.parseNet(sections.body("HP_NET"))
        let addrByIface = Self.parseAddr(sections.body("HP_ADDR"))
        let diskIOCounters = Self.parseDiskIO(sections.body("HP_DISKIO"))
        let memory = Self.parseMeminfo(sections.body("HP_MEM"))
        var disks = Self.parseDF(sections.body("HP_DISK"))
        let processes = Self.parseProcesses(sections.body("HP_PROC"))
        let dockerStatus = Self.parseDockerPS(sections.body("HP_DOCKERPS"))
        let dockerRaw = Self.parseDockerStats(sections.body("HP_DOCKER"), status: dockerStatus)

        var cpuUsage: Double?
        var cpuTimes: CPUTimes?
        if let current = cpuStat.aggregate, let lastCPU {
            cpuUsage = CPUSnapshot.usage(previous: lastCPU, current: current)
            cpuTimes = CPUSnapshot.times(previous: lastCPU, current: current)
        }

        var cores: [CoreSample] = []
        for index in cpuStat.cores.keys.sorted() {
            guard let current = cpuStat.cores[index] else { continue }
            var usage: Double?
            if let previous = lastCores[index] {
                usage = CPUSnapshot.usage(previous: previous, current: current)
            }
            cores.append(CoreSample(index: index, usage: usage))
        }

        var rxRate: Double?
        var txRate: Double?
        var diskReadRate: Double?
        var diskWriteRate: Double?
        var interfaces: [InterfaceSample] = []
        var containers: [ContainerSample] = []

        if let lastSampleAt {
            let dt = date.timeIntervalSince(lastSampleAt)
            if dt > 0.2 {
                var rx: UInt64 = 0
                var tx: UInt64 = 0
                for (name, current) in ifaceCounters where Self.shouldCountInterface(name) {
                    rx &+= current.rx
                    tx &+= current.tx
                    let previous = lastIfaces[name]
                    let receiveRate: Double?
                    let transmitRate: Double?
                    if let previous {
                        receiveRate = max(0, Double(current.rx.subtractingReportingOverflow(previous.rx).partialValue) / dt)
                        transmitRate = max(0, Double(current.tx.subtractingReportingOverflow(previous.tx).partialValue) / dt)
                    } else {
                        receiveRate = nil
                        transmitRate = nil
                    }
                    interfaces.append(
                        InterfaceSample(
                            name: name,
                            ipv4CIDR: addrByIface[name],
                            receiveBytes: current.rx,
                            transmitBytes: current.tx,
                            receiveBytesPerSecond: receiveRate,
                            transmitBytesPerSecond: transmitRate
                        )
                    )
                }
                let previousRx = lastIfaces.reduce(into: UInt64(0)) { sum, item in
                    if Self.shouldCountInterface(item.key) { sum &+= item.value.rx }
                }
                let previousTx = lastIfaces.reduce(into: UInt64(0)) { sum, item in
                    if Self.shouldCountInterface(item.key) { sum &+= item.value.tx }
                }
                if !lastIfaces.isEmpty {
                    rxRate = max(0, Double(rx.subtractingReportingOverflow(previousRx).partialValue) / dt)
                    txRate = max(0, Double(tx.subtractingReportingOverflow(previousTx).partialValue) / dt)
                }
                let hostRead = Self.sumHostDiskBytes(diskIOCounters, \.readBytes)
                let hostWrite = Self.sumHostDiskBytes(diskIOCounters, \.writeBytes)
                let previousHostRead = Self.sumHostDiskBytes(lastDiskDevices, \.readBytes)
                let previousHostWrite = Self.sumHostDiskBytes(lastDiskDevices, \.writeBytes)
                if !lastDiskDevices.isEmpty {
                    diskReadRate = max(0, Double(hostRead.subtractingReportingOverflow(previousHostRead).partialValue) / dt)
                    diskWriteRate = max(0, Double(hostWrite.subtractingReportingOverflow(previousHostWrite).partialValue) / dt)
                }
                Self.applyDiskIO(&disks, current: diskIOCounters, previous: lastDiskDevices, dt: dt)
                for item in dockerRaw {
                    var next = item
                    if let previous = lastDocker[item.name] {
                        next.netReceiveBytesPerSecond = max(
                            0,
                            Double(item.netReceiveBytes.subtractingReportingOverflow(previous.rx).partialValue) / dt
                        )
                        next.netTransmitBytesPerSecond = max(
                            0,
                            Double(item.netTransmitBytes.subtractingReportingOverflow(previous.tx).partialValue) / dt
                        )
                        next.blockReadBytesPerSecond = max(
                            0,
                            Double(item.blockReadBytes.subtractingReportingOverflow(previous.blockRead).partialValue) / dt
                        )
                        next.blockWriteBytesPerSecond = max(
                            0,
                            Double(item.blockWriteBytes.subtractingReportingOverflow(previous.blockWrite).partialValue) / dt
                        )
                    }
                    containers.append(next)
                }
            } else {
                interfaces = ifaceCounters.compactMap { name, counters in
                    guard Self.shouldCountInterface(name) else { return nil }
                    return InterfaceSample(
                        name: name,
                        ipv4CIDR: addrByIface[name],
                        receiveBytes: counters.rx,
                        transmitBytes: counters.tx
                    )
                }
                Self.applyDiskIO(&disks, current: diskIOCounters, previous: [:], dt: 0)
                containers = dockerRaw
            }
        } else {
            interfaces = ifaceCounters.compactMap { name, counters in
                guard Self.shouldCountInterface(name) else { return nil }
                return InterfaceSample(
                    name: name,
                    ipv4CIDR: addrByIface[name],
                    receiveBytes: counters.rx,
                    transmitBytes: counters.tx
                )
            }
            Self.applyDiskIO(&disks, current: diskIOCounters, previous: [:], dt: 0)
            containers = dockerRaw
        }

        interfaces.sort { $0.name < $1.name }
        containers.sort { $0.name < $1.name }

        lastCPU = cpuStat.aggregate
        lastCores = cpuStat.cores
        lastIfaces = ifaceCounters
        lastDiskDevices = diskIOCounters
        lastDocker = Dictionary(uniqueKeysWithValues: dockerRaw.map {
            ($0.name, DockerIO(rx: $0.netReceiveBytes, tx: $0.netTransmitBytes, blockRead: $0.blockReadBytes, blockWrite: $0.blockWriteBytes))
        })
        lastSampleAt = date

        return HostMetrics(
            hostname: hostname,
            operatingSystem: os,
            osPrettyName: osPrettyName,
            osID: osID,
            cpuModel: cpuModel,
            uptimeSeconds: uptime,
            loadAverage: load,
            cpuCores: cpuCores,
            cpuUsage: cpuUsage,
            cpuTimes: cpuTimes,
            cores: cores,
            memoryTotalBytes: memory.total,
            memoryAvailableBytes: memory.available,
            memoryFreeBytes: memory.free,
            memoryCachedBytes: memory.cached,
            swapTotalBytes: memory.swapTotal,
            swapFreeBytes: memory.swapFree,
            disks: disks,
            interfaces: interfaces,
            netReceiveBytesPerSecond: rxRate,
            netTransmitBytesPerSecond: txRate,
            diskReadBytesPerSecond: diskReadRate,
            diskWriteBytesPerSecond: diskWriteRate,
            processes: processes,
            containers: containers,
            dockerEngineVersion: sections.field("docker_engine") ?? "",
            dockerImageCount: Int(sections.field("docker_images") ?? "") ?? 0,
            dockerRunningCount: Int(sections.field("docker_running") ?? "") ?? 0,
            dockerStoppedCount: Int(sections.field("docker_stopped") ?? "") ?? 0,
            sampledAt: date
        )
    }

    private static func parseLoadAverage(_ raw: String?) -> (Double, Double, Double)? {
        guard let raw else { return nil }
        let parts = raw.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 3,
              let a = Double(parts[0]),
              let b = Double(parts[1]),
              let c = Double(parts[2])
        else { return nil }
        return (a, b, c)
    }

    private static func parseCPUStat(_ body: String) -> (aggregate: CPUSnapshot?, cores: [Int: CPUSnapshot]) {
        var aggregate: CPUSnapshot?
        var cores: [Int: CPUSnapshot] = [:]
        for line in body.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard let label = parts.first else { continue }
            let fields = parts.dropFirst().compactMap { UInt64($0) }
            guard let snapshot = CPUSnapshot.parse(Array(fields)) else { continue }
            if label == "cpu" {
                aggregate = snapshot
            } else if label.hasPrefix("cpu"), let index = Int(label.dropFirst(3)) {
                cores[index] = snapshot
            }
        }
        return (aggregate, cores)
    }

    private static func parseMeminfo(_ body: String) -> (
        total: UInt64,
        available: UInt64,
        free: UInt64,
        cached: UInt64,
        swapTotal: UInt64,
        swapFree: UInt64
    ) {
        var values: [String: UInt64] = [:]
        for line in body.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == ":" || $0 == " " || $0 == "\t" })
                .map(String.init)
                .filter { !$0.isEmpty }
            guard parts.count >= 2, let kb = UInt64(parts[1]) else { continue }
            values[parts[0]] = kb &* 1024
        }
        let cached = (values["Cached"] ?? 0) &+ (values["Buffers"] ?? 0) &+ (values["SReclaimable"] ?? 0)
        return (
            values["MemTotal"] ?? 0,
            values["MemAvailable"] ?? 0,
            values["MemFree"] ?? 0,
            cached,
            values["SwapTotal"] ?? 0,
            values["SwapFree"] ?? 0
        )
    }

    private static func parseNet(_ body: String) -> [String: IfaceCounters] {
        var result: [String: IfaceCounters] = [:]
        for line in body.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let name = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
            let rest = trimmed[trimmed.index(after: colon)...]
            let fields = rest.split(whereSeparator: \.isWhitespace).compactMap { UInt64($0) }
            guard fields.count >= 9 else { continue }
            result[String(name)] = IfaceCounters(rx: fields[0], tx: fields[8])
        }
        return result
    }

    private static func parseDiskIO(_ body: String) -> [String: DeviceIOCounters] {
        var result: [String: DeviceIOCounters] = [:]
        for line in body.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 11 else { continue }
            let name = fields[2]
            guard shouldKeepDiskstats(name) else { continue }
            guard
                let readOps = UInt64(fields[3]),
                let sectorsRead = UInt64(fields[5]),
                let readTime = UInt64(fields[6]),
                let writeOps = UInt64(fields[7]),
                let sectorsWritten = UInt64(fields[9]),
                let writeTime = UInt64(fields[10])
            else { continue }
            result[name] = DeviceIOCounters(
                readOps: readOps,
                writeOps: writeOps,
                readBytes: sectorsRead &* 512,
                writeBytes: sectorsWritten &* 512,
                readTimeMs: readTime,
                writeTimeMs: writeTime
            )
        }
        return result
    }

    private static func shouldKeepDiskstats(_ name: String) -> Bool {
        let skipPrefixes = ["loop", "ram", "zram", "sr", "fd", "nbd"]
        return !skipPrefixes.contains(where: { name == $0 || name.hasPrefix($0) })
    }

    private static func shouldCountDiskDevice(_ name: String) -> Bool {
        let skipPrefixes = ["loop", "ram", "zram", "sr", "fd", "dm-", "md", "nbd", "synoboot"]
        if skipPrefixes.contains(where: { name == $0 || name.hasPrefix($0) }) {
            return false
        }
        if name.range(of: #"^(sd|vd|hd|xvd)[a-z]+\d+$"#, options: .regularExpression) != nil {
            return false
        }
        if name.range(of: #"p\d+$"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private static func sumHostDiskBytes(
        _ devices: [String: DeviceIOCounters],
        _ keyPath: KeyPath<DeviceIOCounters, UInt64>
    ) -> UInt64 {
        devices.reduce(into: UInt64(0)) { sum, item in
            guard shouldCountDiskDevice(item.key) else { return }
            sum &+= item.value[keyPath: keyPath]
        }
    }

    private static func diskstatsName(for filesystem: String) -> String {
        if filesystem.hasPrefix("/dev/") {
            return URL(fileURLWithPath: filesystem).lastPathComponent
        }
        return filesystem
    }

    private static func applyDiskIO(
        _ disks: inout [DiskSample],
        current: [String: DeviceIOCounters],
        previous: [String: DeviceIOCounters],
        dt: TimeInterval
    ) {
        for index in disks.indices {
            let name = diskstatsName(for: disks[index].filesystem)
            guard let now = current[name] else { continue }
            disks[index].readBytes = now.readBytes
            disks[index].writeBytes = now.writeBytes
            guard dt > 0.2, let last = previous[name] else { continue }
            let readOps = now.readOps.subtractingReportingOverflow(last.readOps).partialValue
            let writeOps = now.writeOps.subtractingReportingOverflow(last.writeOps).partialValue
            let readTime = now.readTimeMs.subtractingReportingOverflow(last.readTimeMs).partialValue
            let writeTime = now.writeTimeMs.subtractingReportingOverflow(last.writeTimeMs).partialValue
            disks[index].readBytesPerSecond = max(
                0,
                Double(now.readBytes.subtractingReportingOverflow(last.readBytes).partialValue) / dt
            )
            disks[index].writeBytesPerSecond = max(
                0,
                Double(now.writeBytes.subtractingReportingOverflow(last.writeBytes).partialValue) / dt
            )
            disks[index].readIOPS = max(0, Double(readOps) / dt)
            disks[index].writeIOPS = max(0, Double(writeOps) / dt)
            disks[index].readLatencyMs = readOps > 0 ? Double(readTime) / Double(readOps) : 0
            disks[index].writeLatencyMs = writeOps > 0 ? Double(writeTime) / Double(writeOps) : 0
        }
    }

    private static func parseAddr(_ body: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in body.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let inet = parts.firstIndex(of: "inet"), inet + 1 < parts.count, inet >= 1 else { continue }
            let cidr = parts[inet + 1]
            guard cidr.contains("/") else { continue }
            var name = parts[inet - 1]
            if name.hasSuffix(":"), inet >= 2 {
                name = parts[inet - 2]
            }
            if name.hasSuffix(":") { continue }
            if result[name] == nil {
                result[name] = cidr
            }
        }
        return result
    }

    static func shouldCountInterface(_ name: String) -> Bool {
        let skipPrefixes = [
            "lo", "sit", "docker", "veth", "br-", "tun", "tap", "virbr",
            "cni", "flannel", "calico", "kube", "fwbr", "fwln", "fwpr", "tailscale"
        ]
        return !skipPrefixes.contains { name == $0 || name.hasPrefix($0) }
    }

    private static func parseDF(_ body: String) -> [DiskSample] {
        var disks: [DiskSample] = []
        for line in body.split(separator: "\n").dropFirst() {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 6 else { continue }
            let hasType = UInt64(fields[1]) == nil
            let filesystem = fields[0]
            let fstype = hasType ? fields[1] : ""
            let totalIndex = hasType ? 2 : 1
            let usedIndex = hasType ? 3 : 2
            let mount = fields[fields.count - 1]
            if filesystem.hasPrefix("tmpfs") || filesystem.hasPrefix("devtmpfs") || filesystem.hasPrefix("overlay") {
                continue
            }
            if mount.hasPrefix("/run") || mount.hasPrefix("/dev") || mount.hasPrefix("/proc") {
                continue
            }
            guard totalIndex < fields.count, usedIndex < fields.count,
                  let total = UInt64(fields[totalIndex]), let used = UInt64(fields[usedIndex])
            else { continue }
            disks.append(
                DiskSample(
                    filesystem: filesystem,
                    fstype: fstype,
                    totalBytes: total,
                    usedBytes: used,
                    mount: mount
                )
            )
        }
        return disks
    }

    private static func parseProcesses(_ body: String) -> [ProcessSample] {
        var processes: [ProcessSample] = []
        var seen = Set<Int>()
        for line in body.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 6, let pid = Int(fields[0]), let rssKB = UInt64(fields[4]) else { continue }
            if seen.contains(pid) { continue }
            seen.insert(pid)
            processes.append(
                ProcessSample(
                    pid: pid,
                    user: fields[1],
                    command: fields[5...].joined(separator: " "),
                    cpuPercent: Double(fields[2]) ?? 0,
                    memoryPercent: Double(fields[3]) ?? 0,
                    rssBytes: rssKB &* 1024
                )
            )
        }
        return processes
    }

    private static func parseDockerPS(_ body: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in body.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count >= 1, !parts[0].isEmpty else { continue }
            result[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return result
    }

    private static func parseDockerStats(_ body: String, status: [String: String]) -> [ContainerSample] {
        var containers: [ContainerSample] = []
        for line in body.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 6 else { continue }
            let name = parts[0]
            guard !name.isEmpty, name != "NAME" else { continue }
            let memParts = parts[3].split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            let netParts = parts[4].split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            let blockParts = parts[5].split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            containers.append(
                ContainerSample(
                    name: name,
                    status: status[name] ?? "",
                    cpuRatio: parsePercentRatio(parts[1]),
                    memoryRatio: parsePercentRatio(parts[2]),
                    memoryUsedBytes: memParts.first.flatMap { parseDataSize($0) } ?? 0,
                    memoryLimitBytes: memParts.dropFirst().first.flatMap { parseDataSize($0) } ?? 0,
                    netReceiveBytes: netParts.first.flatMap { parseDataSize($0) } ?? 0,
                    netTransmitBytes: netParts.dropFirst().first.flatMap { parseDataSize($0) } ?? 0,
                    blockReadBytes: blockParts.first.flatMap { parseDataSize($0) } ?? 0,
                    blockWriteBytes: blockParts.dropFirst().first.flatMap { parseDataSize($0) } ?? 0
                )
            )
        }
        return containers
    }
}

private struct CPUSnapshot {
    var user: UInt64
    var nice: UInt64
    var system: UInt64
    var idle: UInt64
    var iowait: UInt64
    var irq: UInt64
    var softirq: UInt64
    var steal: UInt64
    var total: UInt64

    var idleAndWait: UInt64 { idle &+ iowait }

    static func parse(_ fields: [UInt64]) -> CPUSnapshot? {
        guard fields.count >= 4 else { return nil }
        let user = fields[0]
        let nice = fields.count > 1 ? fields[1] : 0
        let system = fields.count > 2 ? fields[2] : 0
        let idle = fields[3]
        let iowait = fields.count > 4 ? fields[4] : 0
        let irq = fields.count > 5 ? fields[5] : 0
        let softirq = fields.count > 6 ? fields[6] : 0
        let steal = fields.count > 7 ? fields[7] : 0
        let total = fields.reduce(UInt64(0), +)
        return CPUSnapshot(
            user: user,
            nice: nice,
            system: system,
            idle: idle,
            iowait: iowait,
            irq: irq,
            softirq: softirq,
            steal: steal,
            total: total
        )
    }

    static func usage(previous: CPUSnapshot, current: CPUSnapshot) -> Double? {
        let idleDelta = current.idleAndWait.subtractingReportingOverflow(previous.idleAndWait).partialValue
        let totalDelta = current.total.subtractingReportingOverflow(previous.total).partialValue
        guard totalDelta > 0 else { return nil }
        return min(max(1 - (Double(idleDelta) / Double(totalDelta)), 0), 1)
    }

    static func times(previous: CPUSnapshot, current: CPUSnapshot) -> CPUTimes? {
        let totalDelta = current.total.subtractingReportingOverflow(previous.total).partialValue
        guard totalDelta > 0 else { return nil }
        let share: (UInt64, UInt64) -> Double = { currentValue, previousValue in
            Double(currentValue.subtractingReportingOverflow(previousValue).partialValue) / Double(totalDelta)
        }
        return CPUTimes(
            user: share(current.user, previous.user),
            nice: share(current.nice, previous.nice),
            system: share(current.system, previous.system),
            iowait: share(current.iowait, previous.iowait),
            irq: share(current.irq &+ current.softirq, previous.irq &+ previous.softirq),
            steal: share(current.steal, previous.steal),
            usage: usage(previous: previous, current: current) ?? 0
        )
    }
}

private struct IfaceCounters {
    var rx: UInt64
    var tx: UInt64
}

private struct DeviceIOCounters {
    var readOps: UInt64
    var writeOps: UInt64
    var readBytes: UInt64
    var writeBytes: UInt64
    var readTimeMs: UInt64
    var writeTimeMs: UInt64
}

private struct DockerIO {
    var rx: UInt64
    var tx: UInt64
    var blockRead: UInt64
    var blockWrite: UInt64
}

private struct SectionMap {
    private var fields: [String: String] = [:]
    private var bodies: [String: String] = [:]

    init(text: String) {
        var currentBodyKey: String?
        var currentBody: [String] = []

        func flushBody() {
            if let currentBodyKey {
                bodies[currentBodyKey] = currentBody.joined(separator: "\n")
            }
            currentBodyKey = nil
            currentBody.removeAll(keepingCapacity: true)
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            switch line {
            case "HP_BEGIN":
                flushBody()
            case "HP_STAT", "HP_MEM", "HP_NET", "HP_ADDR", "HP_DISK", "HP_DISKIO", "HP_PROC", "HP_DOCKER", "HP_DOCKERPS":
                flushBody()
                currentBodyKey = line
            case "HP_END":
                flushBody()
            default:
                if currentBodyKey != nil {
                    currentBody.append(line)
                } else if let eq = line.firstIndex(of: "=") {
                    let key = String(line[..<eq])
                    let value = String(line[line.index(after: eq)...])
                    fields[key] = value
                }
            }
        }
        flushBody()
    }

    func field(_ key: String) -> String? { fields[key] }
    func body(_ key: String) -> String { bodies[key] ?? "" }
}
