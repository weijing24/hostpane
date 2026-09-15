import Foundation

public enum DockerProbe {
    public static let detectCommand = #"""
    LANG=C LC_ALL=C
    echo HP_BEGIN
    echo "docker_bin=$(command -v docker 2>/dev/null || true)"
    echo "context=$(docker context show 2>/dev/null || echo default)"
    sock=""
    for candidate in /var/run/docker.sock /run/docker.sock "$HOME/.docker/run/docker.sock" /var/run/docker.sock.raw; do
      if [ -S "$candidate" ]; then
        if [ -z "$sock" ]; then sock="$candidate"; fi
        echo "socket_found=$candidate"
        if [ -w "$candidate" ]; then echo "socket_writable=$candidate"; fi
      fi
    done
    echo "socket=$sock"
    echo HP_VERSION
    docker version --format '{{.Server.Version}}|{{.Server.APIVersion}}|{{.Server.Os}}|{{.Server.Arch}}' 2>/dev/null || true
    echo HP_INFO
    docker info --format '{{.OperatingSystem}}|{{.Architecture}}|{{.NCPU}}|{{.MemTotal}}' 2>/dev/null || true
    echo HP_END
    """#

    /// Fast inventory for first paint: no stats (1–2s), no system df, no events, no bulk inspect.
    public static let snapshotCommand = #"""
    LANG=C LC_ALL=C
    echo HP_BEGIN
    echo HP_PS
    docker ps -a --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}|{{.Ports}}|{{.CreatedAt}}|{{.Labels}}|{{.Mounts}}|{{.Networks}}' 2>/dev/null | head -n 200
    echo HP_IMAGES
    docker images --digests --format '{{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedSince}}|{{.Digest}}' 2>/dev/null | head -n 200
    echo HP_VOLUMES
    docker volume ls --format '{{.Name}}|{{.Driver}}|{{.Mountpoint}}' 2>/dev/null | head -n 200
    echo HP_NETWORKS
    docker network ls --format '{{.ID}}|{{.Name}}|{{.Driver}}|{{.Scope}}' 2>/dev/null | head -n 200
    echo HP_NETINSPECT
    nids=$(docker network ls -q 2>/dev/null)
    if [ -n "$nids" ]; then docker network inspect $nids 2>/dev/null; else echo []; fi
    echo HP_COMPOSE
    docker compose ls -a --format '{{.Name}}|{{.Status}}|{{.ConfigFiles}}' 2>/dev/null || true
    echo HP_END
    """#

    public static let liveCommand = #"""
    LANG=C LC_ALL=C
    echo HP_BEGIN
    echo HP_PS
    docker ps -a --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}|{{.Ports}}|{{.CreatedAt}}|{{.Labels}}|{{.Mounts}}|{{.Networks}}' 2>/dev/null | head -n 200
    echo HP_STATS
    docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}' 2>/dev/null | head -n 200
    echo HP_END
    """#

    public static let diskCommand = #"""
    LANG=C LC_ALL=C
    echo HP_BEGIN
    echo HP_DF
    docker system df --format '{{.Type}}|{{.TotalCount}}|{{.Active}}|{{.Size}}|{{.Reclaimable}}' 2>/dev/null || true
    echo HP_END
    """#

    public static let eventsCommand = #"""
    LANG=C LC_ALL=C
    echo HP_BEGIN
    echo HP_EVENTS
    docker events --since 2h --until 0s --format '{{json .}}' 2>/dev/null | tail -n 200
    echo HP_END
    """#

    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func actionCommand(_ verb: String, name: String) -> String {
        "docker \(verb) -- \(shellQuote(name))"
    }

    public static func logsCommand(name: String) -> String {
        "docker logs --tail 200 --timestamps \(shellQuote(name)) 2>&1"
    }

    public static func topCommand(name: String) -> String {
        "docker top \(shellQuote(name)) 2>&1"
    }

    public static func inspectCommand(name: String) -> String {
        "docker inspect \(shellQuote(name)) 2>&1"
    }

    public static func imageHistoryCommand(name: String) -> String {
        "docker history --format '{{.CreatedBy}}|{{.Size}}' \(shellQuote(name)) 2>/dev/null"
    }

    public static func imageRemoveCommand(name: String) -> String {
        "docker rmi \(shellQuote(name))"
    }

    public static func imageTagCommand(source: String, target: String) -> String {
        "docker tag \(shellQuote(source)) \(shellQuote(target))"
    }

    public static func volumeInspectCommand(name: String) -> String {
        "docker volume inspect \(shellQuote(name)) 2>&1"
    }

    public static func volumeRemoveCommand(name: String) -> String {
        "docker volume rm \(shellQuote(name))"
    }

    public static let volumePruneCommand = "docker volume prune -f"

    public static func networkInspectCommand(name: String) -> String {
        "docker network inspect \(shellQuote(name)) 2>&1"
    }

    public static func networkRemoveCommand(name: String) -> String {
        "docker network rm \(shellQuote(name))"
    }
}

public struct DockerParser {
    public init() {}

    public func parseDetect(_ text: String) throws -> DockerEngineInfo {
        let sections = DockerSectionMap(text: text)
        let cli = sections.field("docker_bin") ?? ""
        if cli.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DockerProbeError.missingCLI
        }
        let engine = parseEngine(sections)
        if engine.version.isEmpty {
            throw DockerProbeError.engineUnavailable("docker CLI 在 \(cli)，但引擎没有响应。")
        }
        return engine
    }

    public func parseSnapshot(_ text: String, at date: Date = Date()) throws -> DockerSnapshot {
        let sections = DockerSectionMap(text: text)
        let engine = parseEngine(sections)
        let stats = parseStats(sections.body("HP_STATS"))
        var containers = parseContainers(sections.body("HP_PS"))
        applyStats(&containers, stats)
        applyInspect(&containers, sections.body("HP_INSPECT"))
        return DockerSnapshot(
            engine: engine,
            disk: parseDisk(sections.body("HP_DF")),
            containers: containers,
            images: parseImages(sections.body("HP_IMAGES")),
            volumes: parseVolumes(sections.body("HP_VOLUMES")),
            networks: applyNetworkInspect(
                parseNetworks(sections.body("HP_NETWORKS")),
                sections.body("HP_NETINSPECT")
            ),
            compose: parseCompose(sections.body("HP_COMPOSE")),
            events: parseEvents(sections.body("HP_EVENTS")),
            sampledAt: date
        )
    }

    public func mergeLive(_ existing: DockerSnapshot, text: String, at date: Date = Date()) -> DockerSnapshot {
        let sections = DockerSectionMap(text: text)
        let stats = parseStats(sections.body("HP_STATS"))
        var containers = parseContainers(sections.body("HP_PS"))
        if containers.isEmpty {
            containers = existing.containers
        } else {
            applyStats(&containers, stats)
            let previous = Dictionary(uniqueKeysWithValues: existing.containers.map { ($0.name, $0) })
            for index in containers.indices {
                guard let old = previous[containers[index].name] else { continue }
                if containers[index].health.isEmpty { containers[index].health = old.health }
                if containers[index].created.isEmpty { containers[index].created = old.created }
                if containers[index].composeProject.isEmpty { containers[index].composeProject = old.composeProject }
                if containers[index].composeService.isEmpty { containers[index].composeService = old.composeService }
                containers[index].command = old.command
                containers[index].restartPolicy = old.restartPolicy
                containers[index].networkMode = old.networkMode
                containers[index].pid = old.pid
                containers[index].mounts = old.mounts
                containers[index].env = old.env
                if containers[index].volumeNames.isEmpty { containers[index].volumeNames = old.volumeNames }
                if containers[index].networkNames.isEmpty { containers[index].networkNames = old.networkNames }
                if containers[index].networkMode.isEmpty { containers[index].networkMode = old.networkMode }
                if containers[index].containerID.count < old.containerID.count {
                    containers[index].containerID = old.containerID
                }
            }
        }
        var next = existing
        let disk = parseDisk(sections.body("HP_DF"))
        if disk.totalBytes > 0 || disk.images.count > 0 {
            next.disk = disk
        }
        next.containers = containers
        next.sampledAt = date
        return next
    }

    private func parseEngine(_ sections: DockerSectionMap) -> DockerEngineInfo {
        let versionLine = sections.body("HP_VERSION").split(separator: "\n").map(String.init).first { !$0.isEmpty } ?? ""
        let versionParts = versionLine.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let infoLine = sections.body("HP_INFO").split(separator: "\n").map(String.init).first { !$0.isEmpty } ?? ""
        let infoParts = infoLine.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let socket = sections.field("socket") ?? ""
        let writable = (sections.field("socket_writable") ?? "").isEmpty == false
        var os = versionParts.count > 2 ? versionParts[2] : ""
        var arch = versionParts.count > 3 ? versionParts[3] : ""
        if os.isEmpty, infoParts.count > 0 { os = infoParts[0] }
        if arch.isEmpty, infoParts.count > 1 { arch = infoParts[1] }
        return DockerEngineInfo(
            version: versionParts.first ?? "",
            apiVersion: versionParts.count > 1 ? versionParts[1] : "",
            os: os,
            arch: arch,
            socket: socket,
            context: sections.field("context") ?? "default",
            cliPath: sections.field("docker_bin") ?? "",
            socketWritable: writable
        )
    }

    private func parseDisk(_ body: String) -> DockerDiskUsage {
        var usage = DockerDiskUsage()
        for line in body.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5 else { continue }
            let slice = DockerDiskSlice(
                count: Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0,
                active: Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0,
                sizeBytes: parseDockerSize(parts[3]) ?? 0,
                reclaimableBytes: parseDockerSize(parts[4]) ?? 0,
                reclaimablePercent: parseReclaimablePercent(parts[4])
            )
            switch parts[0].lowercased() {
            case "images", "image":
                usage.images = slice
            case "containers", "container":
                usage.containers = slice
            case "local volumes", "volumes", "volume":
                usage.volumes = slice
            case "build cache", "buildcache", "cache":
                usage.buildCache = slice
            default:
                break
            }
        }
        return usage
    }

    private func parseContainers(_ body: String) -> [DockerContainer] {
        var rows: [DockerContainer] = []
        for line in body.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5 else { continue }
            let name = parts[1]
            guard !name.isEmpty, name != "NAMES" else { continue }
            let status = parts[4]
            let labels = parts.count > 7 ? parts[7] : (parts.count > 6 && parts[6].contains("=") ? parts[6] : "")
            let created = parts.count > 6 && !parts[6].contains("=") ? parts[6] : ""
            let compose = composeFromLabels(labels)
            let volumeNames = parts.count > 8
                ? parts[8].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                : []
            let networkNames = parts.count > 9
                ? parts[9].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                : []
            rows.append(
                DockerContainer(
                    containerID: parts[0],
                    name: name,
                    image: parts[2],
                    state: parts[3],
                    status: status,
                    ports: parts.count > 5 ? parts[5] : "",
                    health: healthFromStatus(status),
                    created: created,
                    composeProject: compose.project,
                    composeService: compose.service,
                    volumeNames: volumeNames,
                    networkNames: networkNames
                )
            )
        }
        return rows
    }

    private func applyStats(_ containers: inout [DockerContainer], _ stats: [String: StatsSample]) {
        for index in containers.indices {
            guard let sample = stats[containers[index].name] else { continue }
            containers[index].cpuRatio = sample.cpuRatio
            containers[index].memoryRatio = sample.memoryRatio
            containers[index].memoryUsedBytes = sample.memoryUsedBytes
            containers[index].memoryLimitBytes = sample.memoryLimitBytes
            containers[index].netReceiveBytes = sample.netReceiveBytes
            containers[index].netTransmitBytes = sample.netTransmitBytes
            containers[index].blockReadBytes = sample.blockReadBytes
            containers[index].blockWriteBytes = sample.blockWriteBytes
        }
    }

    public func mergeInspectJSON(_ text: String, into existing: DockerSnapshot) -> DockerSnapshot {
        var containers = existing.containers
        applyInspect(&containers, text)
        var next = existing
        next.containers = containers
        return next
    }

    public func mergeEvents(_ text: String, into existing: DockerSnapshot) -> DockerSnapshot {
        let sections = DockerSectionMap(text: text)
        var next = existing
        next.events = parseEvents(sections.body("HP_EVENTS"))
        return next
    }

    public func mergeImageHistory(_ historyText: String, imageID: String, into existing: DockerSnapshot) -> DockerSnapshot {
        var images = existing.images
        let layers = parseImageHistory(historyText)
        for index in images.indices where matchesImage(images[index], imageID) {
            images[index].layers = layers
            images[index].historyLoaded = true
        }
        var next = existing
        next.images = images
        return next
    }

    public func mergeImageInspect(_ inspectJSON: String, imageID: String, into existing: DockerSnapshot) -> DockerSnapshot {
        var images = existing.images
        guard let detail = parseImageInspect(inspectJSON) else { return existing }
        for index in images.indices where matchesImage(images[index], imageID) {
            if !detail.imageID.isEmpty { images[index].imageID = detail.imageID }
            if !detail.digest.isEmpty { images[index].digest = detail.digest }
            if !detail.createdAt.isEmpty { images[index].createdAt = detail.createdAt }
            if !detail.sizeLabel.isEmpty { images[index].sizeLabel = detail.sizeLabel }
            if !detail.sharedSizeLabel.isEmpty { images[index].sharedSizeLabel = detail.sharedSizeLabel }
            if !detail.repoTags.isEmpty { images[index].repoTags = detail.repoTags }
        }
        var next = existing
        next.images = images
        return next
    }

    private func matchesImage(_ image: DockerImage, _ imageID: String) -> Bool {
        image.id == imageID || image.shortID == imageID || image.reference == imageID
    }

    public func mergeNetworkInspect(_ inspectJSON: String, name: String, into existing: DockerSnapshot) -> DockerSnapshot {
        var networks = existing.networks
        networks = applyNetworkInspect(networks, inspectJSON)
        var next = existing
        next.networks = networks
        return next
    }

    private func applyNetworkInspect(_ networks: [DockerNetwork], _ body: String) -> [DockerNetwork] {
        let details = parseNetworkInspectList(body)
        guard !details.isEmpty else { return networks }
        var result = networks
        for index in result.indices {
            let match = details.first { $0.name == result[index].name || $0.shortID == result[index].shortID }
            guard let detail = match else { continue }
            if !detail.networkID.isEmpty { result[index].networkID = detail.networkID }
            if !detail.driver.isEmpty { result[index].driver = detail.driver }
            if !detail.scope.isEmpty { result[index].scope = detail.scope }
            result[index].subnet = detail.subnet
            result[index].gateway = detail.gateway
            result[index].inspectLoaded = true
        }
        return result
    }

    private func parseNetworkInspectList(_ body: String) -> [DockerNetwork] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[]" else { return [] }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return [] }
        let objects: [[String: Any]]
        if let array = json as? [[String: Any]] {
            objects = array
        } else if let object = json as? [String: Any] {
            objects = [object]
        } else {
            return []
        }
        return objects.compactMap(parseNetworkInspectObject)
    }

    private func parseNetworkInspectObject(_ object: [String: Any]) -> DockerNetwork? {
        let name = stringValue(object["Name"])
        guard !name.isEmpty else { return nil }
        let ipam = object["IPAM"] as? [String: Any] ?? [:]
        let configs = ipam["Config"] as? [[String: Any]] ?? []
        let first = configs.first ?? [:]
        return DockerNetwork(
            networkID: stringValue(object["Id"]),
            name: name,
            driver: stringValue(object["Driver"]),
            scope: stringValue(object["Scope"]),
            subnet: stringValue(first["Subnet"]),
            gateway: stringValue(first["Gateway"]),
            inspectLoaded: true
        )
    }

    public func mergeVolumeInspect(_ inspectJSON: String, name: String, into existing: DockerSnapshot) -> DockerSnapshot {
        guard let detail = parseVolumeInspect(inspectJSON) else { return existing }
        var volumes = existing.volumes
        for index in volumes.indices where volumes[index].name == name {
            if !detail.driver.isEmpty { volumes[index].driver = detail.driver }
            if !detail.mountpoint.isEmpty { volumes[index].mountpoint = detail.mountpoint }
            if !detail.scope.isEmpty { volumes[index].scope = detail.scope }
            if !detail.createdAt.isEmpty { volumes[index].createdAt = detail.createdAt }
            volumes[index].labels = detail.labels
            volumes[index].inspectLoaded = true
        }
        var next = existing
        next.volumes = volumes
        return next
    }

    private func parseVolumeInspect(_ body: String) -> DockerVolume? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        let object: [String: Any]
        if let array = json as? [[String: Any]], let first = array.first {
            object = first
        } else if let single = json as? [String: Any] {
            object = single
        } else {
            return nil
        }
        let rawLabels = object["Labels"] as? [String: Any] ?? [:]
        let labels = rawLabels.keys.sorted().map { key in
            DockerLabel(key: key, value: stringValue(rawLabels[key]))
        }
        return DockerVolume(
            name: stringValue(object["Name"]),
            driver: stringValue(object["Driver"]),
            mountpoint: stringValue(object["Mountpoint"]),
            scope: stringValue(object["Scope"]),
            createdAt: stringValue(object["CreatedAt"]),
            labels: labels,
            inspectLoaded: true
        )
    }

    private func composeFromLabels(_ labels: String) -> (project: String, service: String) {
        var project = ""
        var service = ""
        for piece in labels.split(separator: ",") {
            let entry = piece.trimmingCharacters(in: .whitespaces)
            guard let eq = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<eq])
            let value = String(entry[entry.index(after: eq)...])
            if key == "com.docker.compose.project" { project = value }
            if key == "com.docker.compose.service" { service = value }
        }
        return (project, service)
    }

    private func healthFromStatus(_ status: String) -> String {
        if status.contains("(healthy)") { return "healthy" }
        if status.contains("(unhealthy)") { return "unhealthy" }
        if status.contains("health: starting") { return "starting" }
        return ""
    }

    private func applyInspect(_ containers: inout [DockerContainer], _ body: String) {
        let details = parseInspect(body)
        for index in containers.indices {
            let name = containers[index].name
            let id = containers[index].containerID
            let match = details.first { item in
                item.name == name
                    || (!id.isEmpty && (item.containerID.hasPrefix(id) || id.hasPrefix(item.shortID)))
            }
            guard let detail = match else { continue }
            containers[index].containerID = detail.containerID
            if !detail.image.isEmpty { containers[index].image = detail.image }
            if !detail.state.isEmpty { containers[index].state = detail.state }
            containers[index].health = detail.health
            containers[index].created = detail.created
            containers[index].command = detail.command
            containers[index].restartPolicy = detail.restartPolicy
            containers[index].composeProject = detail.composeProject
            containers[index].composeService = detail.composeService
            containers[index].networkMode = detail.networkMode
            containers[index].pid = detail.pid
            containers[index].mounts = detail.mounts
            containers[index].env = detail.env
        }
    }

    private func parseInspect(_ body: String) -> [DockerContainer] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[]" else { return [] }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return [] }
        let objects: [[String: Any]]
        if let array = json as? [[String: Any]] {
            objects = array
        } else if let object = json as? [String: Any] {
            objects = [object]
        } else {
            return []
        }
        return objects.compactMap(parseInspectObject)
    }

    private func parseInspectObject(_ object: [String: Any]) -> DockerContainer? {
        let rawName = stringValue(object["Name"]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let config = object["Config"] as? [String: Any] ?? [:]
        let state = object["State"] as? [String: Any] ?? [:]
        let hostConfig = object["HostConfig"] as? [String: Any] ?? [:]
        let labels = config["Labels"] as? [String: Any] ?? [:]
        let restart = hostConfig["RestartPolicy"] as? [String: Any] ?? [:]
        let health = state["Health"] as? [String: Any] ?? [:]
        let name = rawName.isEmpty ? stringValue(config["Hostname"]) : rawName
        guard !name.isEmpty else { return nil }
        return DockerContainer(
            containerID: stringValue(object["Id"]),
            name: name,
            image: stringValue(config["Image"]),
            state: stringValue(state["Status"]),
            status: stringValue(state["Status"]),
            health: stringValue(health["Status"]),
            created: stringValue(object["Created"]),
            command: commandValue(config),
            restartPolicy: stringValue(restart["Name"]),
            composeProject: stringValue(labels["com.docker.compose.project"]),
            composeService: stringValue(labels["com.docker.compose.service"]),
            networkMode: stringValue(hostConfig["NetworkMode"]),
            pid: intValue(state["Pid"]),
            mounts: parseMounts(object["Mounts"]),
            env: stringArray(config["Env"])
        )
    }

    private func commandValue(_ config: [String: Any]) -> String {
        let cmd = stringArray(config["Cmd"])
        if !cmd.isEmpty { return cmd.joined(separator: " ") }
        return stringArray(config["Entrypoint"]).joined(separator: " ")
    }

    private func parseMounts(_ raw: Any?) -> [DockerMount] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.map { row in
            DockerMount(
                source: stringValue(row["Source"]),
                destination: stringValue(row["Destination"]),
                readOnly: boolValue(row["RW"]) == false,
                type: stringValue(row["Type"])
            )
        }
    }

    private func stringValue(_ raw: Any?) -> String {
        if let value = raw as? String { return value }
        if let value = raw as? NSNumber { return value.stringValue }
        return ""
    }

    private func intValue(_ raw: Any?) -> Int {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) ?? 0 }
        return 0
    }

    private func boolValue(_ raw: Any?) -> Bool {
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        return false
    }

    private func stringArray(_ raw: Any?) -> [String] {
        if let rows = raw as? [String] { return rows }
        if let rows = raw as? [Any] { return rows.compactMap { $0 as? String } }
        return []
    }

    private struct StatsSample {
        var cpuRatio: Double
        var memoryRatio: Double
        var memoryUsedBytes: UInt64
        var memoryLimitBytes: UInt64
        var netReceiveBytes: UInt64
        var netTransmitBytes: UInt64
        var blockReadBytes: UInt64
        var blockWriteBytes: UInt64
    }

    private func parseStats(_ body: String) -> [String: StatsSample] {
        var result: [String: StatsSample] = [:]
        for line in body.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 6 else { continue }
            let name = parts[0]
            guard !name.isEmpty, name != "NAME" else { continue }
            let memParts = parts[3].split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            let netParts = parts[4].split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            let blockParts = parts[5].split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            result[name] = StatsSample(
                cpuRatio: parseUncappedPercentRatio(parts[1]),
                memoryRatio: parsePercentRatio(parts[2]),
                memoryUsedBytes: memParts.first.flatMap { parseDataSize($0) } ?? 0,
                memoryLimitBytes: memParts.dropFirst().first.flatMap { parseDataSize($0) } ?? 0,
                netReceiveBytes: netParts.first.flatMap { parseDataSize($0) } ?? 0,
                netTransmitBytes: netParts.dropFirst().first.flatMap { parseDataSize($0) } ?? 0,
                blockReadBytes: blockParts.first.flatMap { parseDataSize($0) } ?? 0,
                blockWriteBytes: blockParts.dropFirst().first.flatMap { parseDataSize($0) } ?? 0
            )
        }
        return result
    }

    private func parseImages(_ body: String) -> [DockerImage] {
        body.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5, !parts[0].isEmpty, parts[0] != "IMAGE ID" else { return nil }
            return DockerImage(
                imageID: parts[0],
                repository: parts[1],
                tag: parts[2],
                sizeLabel: parts[3],
                created: parts[4],
                digest: parts.count > 5 ? parts[5] : ""
            )
        }
    }

    private func parseImageInspect(_ body: String) -> DockerImage? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        let object: [String: Any]
        if let array = json as? [[String: Any]], let first = array.first {
            object = first
        } else if let single = json as? [String: Any] {
            object = single
        } else {
            return nil
        }
        let tags = stringArray(object["RepoTags"])
        let digests = stringArray(object["RepoDigests"])
        let size = intValue(object["Size"])
        let shared = intValue(object["SharedSize"])
        let firstTag = tags.first ?? ""
        let repo: String
        let tag: String
        if let colon = firstTag.lastIndex(of: ":"), !firstTag.contains("/") || firstTag[colon...].count < 80 {
            repo = String(firstTag[..<colon])
            tag = String(firstTag[firstTag.index(after: colon)...])
        } else if firstTag.isEmpty {
            repo = "<none>"
            tag = "<none>"
        } else {
            repo = firstTag
            tag = "latest"
        }
        return DockerImage(
            imageID: stringValue(object["Id"]),
            repository: repo,
            tag: tag,
            sizeLabel: size > 0 ? formatDockerBytes(UInt64(size)) : "",
            created: stringValue(object["Created"]),
            digest: digests.first ?? "",
            sharedSizeLabel: shared > 0 ? formatDockerBytes(UInt64(shared)) : "",
            createdAt: stringValue(object["Created"]),
            repoTags: tags
        )
    }

    private func parseImageHistory(_ body: String) -> [DockerImageLayer] {
        body.split(separator: "\n").compactMap { line in
            let parts = String(line).split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty, parts[0] != "CREATED BY" else { return nil }
            let createdBy = parts[0].trimmingCharacters(in: .whitespaces)
            guard !createdBy.isEmpty else { return nil }
            return DockerImageLayer(
                createdBy: createdBy,
                sizeLabel: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "0B"
            )
        }
    }

    private func formatDockerBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if unit == 0 { return "\(bytes)B" }
        return String(format: "%.1f%@", value, units[unit])
    }

    private func parseVolumes(_ body: String) -> [DockerVolume] {
        body.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2, !parts[0].isEmpty, parts[0] != "VOLUME NAME" else { return nil }
            return DockerVolume(
                name: parts[0],
                driver: parts[1],
                mountpoint: parts.count > 2 ? parts[2] : ""
            )
        }
    }

    private func parseNetworks(_ body: String) -> [DockerNetwork] {
        body.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 4, !parts[0].isEmpty, parts[0] != "NETWORK ID" else { return nil }
            return DockerNetwork(networkID: parts[0], name: parts[1], driver: parts[2], scope: parts[3])
        }
    }

    private func parseCompose(_ body: String) -> [DockerComposeProject] {
        body.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2, !parts[0].isEmpty, parts[0] != "NAME" else { return nil }
            return DockerComposeProject(
                name: parts[0],
                status: parts[1],
                configFiles: parts.count > 2 ? parts[2] : ""
            )
        }
    }

    private func parseEvents(_ body: String) -> [DockerEvent] {
        body.split(separator: "\n").compactMap { line in
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.hasPrefix("{"), let event = parseEventJSON(trimmed) {
                return event
            }
            let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3, !parts[0].isEmpty else { return nil }
            let unix = TimeInterval(parts[0]) ?? 0
            return DockerEvent(
                timestamp: parts[0],
                unixTime: unix,
                type: parts[1],
                action: parts[2],
                actor: parts.count > 3 ? parts[3] : "",
                image: parts.count > 4 ? parts[4] : ""
            )
        }
    }

    private func parseEventJSON(_ line: String) -> DockerEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let actor = object["Actor"] as? [String: Any] ?? [:]
        let attributes = actor["Attributes"] as? [String: Any] ?? [:]
        let action = stringValue(object["Action"]).isEmpty ? stringValue(object["status"]) : stringValue(object["Action"])
        let type = stringValue(object["Type"])
        guard !action.isEmpty || !type.isEmpty else { return nil }
        let unix: TimeInterval
        if let nano = object["timeNano"] as? NSNumber {
            unix = nano.doubleValue / 1_000_000_000
        } else if let time = object["time"] as? NSNumber {
            unix = time.doubleValue
        } else {
            unix = TimeInterval(stringValue(object["time"])) ?? 0
        }
        let name = stringValue(attributes["name"])
        let image = stringValue(attributes["image"]).isEmpty
            ? stringValue(object["from"])
            : stringValue(attributes["image"])
        return DockerEvent(
            timestamp: unix > 0 ? String(Int(unix)) : stringValue(object["time"]),
            unixTime: unix,
            type: type.isEmpty ? "container" : type,
            action: action,
            actor: name,
            image: image
        )
    }
}

public func parseDockerSize(_ raw: String) -> UInt64? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let withoutParen: String
    if let index = trimmed.firstIndex(of: "(") {
        withoutParen = String(trimmed[..<index]).trimmingCharacters(in: .whitespaces)
    } else {
        withoutParen = trimmed
    }
    return parseDataSize(withoutParen)
}

private func parseUncappedPercentRatio(_ raw: String) -> Double {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")
    guard let value = Double(trimmed) else { return 0 }
    return max(value / 100, 0)
}

public func parseReclaimablePercent(_ raw: String) -> Double? {
    guard let start = raw.firstIndex(of: "("), let end = raw.firstIndex(of: ")") else { return nil }
    let inner = raw[raw.index(after: start)..<end]
    return parsePercentRatio(String(inner))
}

private struct DockerSectionMap {
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

        let markers: Set<String> = [
            "HP_VERSION", "HP_INFO", "HP_DF", "HP_PS", "HP_STATS",
            "HP_IMAGES", "HP_VOLUMES", "HP_NETWORKS", "HP_NETINSPECT", "HP_COMPOSE", "HP_EVENTS", "HP_INSPECT"
        ]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line == "HP_BEGIN" {
                flushBody()
            } else if markers.contains(line) {
                flushBody()
                currentBodyKey = line
            } else if line == "HP_END" {
                flushBody()
            } else if currentBodyKey != nil {
                currentBody.append(line)
            } else if let eq = line.firstIndex(of: "=") {
                let key = String(line[..<eq])
                let value = String(line[line.index(after: eq)...])
                fields[key] = value
            }
        }
        flushBody()
    }

    func field(_ key: String) -> String? { fields[key] }

    func body(_ key: String) -> String { bodies[key] ?? "" }
}
