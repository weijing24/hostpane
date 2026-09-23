import Foundation
import HostpaneCore

enum CheckFailure: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self {
        case .message(let text): return text
        }
    }
}

func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure.message(message) }
}

func metricsChecks() throws {
    var parser = LinuxMetricsParser()
    let first = try parser.consume(
        sample(idle: 100, totalIdleAndBusy: 200, rx: 1_000, tx: 2_000),
        at: Date(timeIntervalSince1970: 1_000)
    )
    try expect(first.hostname == "jp01", "hostname")
    try expect(first.isLinux, "isLinux")
    try expect(first.cpuUsage == nil, "first cpu should be nil")
    try expect(first.cpuCores == 2, "cpu cores")
    try expect(first.memoryTotalBytes == 2_000 * 1024, "mem total")
    try expect(first.disks.contains { $0.mount == "/" && $0.totalBytes == 1_000_000 }, "root disk")
    try expect(first.diskReadBytesPerSecond == nil, "first disk io")

    let second = try parser.consume(
        sample(idle: 140, totalIdleAndBusy: 300, rx: 3_000, tx: 6_000, readSectors: 1_400, writeSectors: 2_800),
        at: Date(timeIntervalSince1970: 1_002)
    )
    guard let cpu = second.cpuUsage else { throw CheckFailure.message("second cpu missing") }
    try expect(abs(cpu - 0.6) < 0.001, "cpu usage \(cpu)")
    try expect(second.netReceiveBytesPerSecond == 1_000, "rx rate \(String(describing: second.netReceiveBytesPerSecond))")
    try expect(second.netTransmitBytesPerSecond == 2_000, "tx rate")
    try expect(second.cpuCores == 2, "second cores")
    guard let diskRead = second.diskReadBytesPerSecond else { throw CheckFailure.message("disk read missing") }
    guard let diskWrite = second.diskWriteBytesPerSecond else { throw CheckFailure.message("disk write missing") }
    try expect(abs(diskRead - 102_400) < 0.1, "disk read \(diskRead)")
    try expect(abs(diskWrite - 204_800) < 0.1, "disk write \(diskWrite)")
    try expect(second.cpuTimes != nil, "cpu times")
    try expect(second.processes.contains { $0.command == "sshd" && $0.pid == 42 }, "process sshd")
    try expect(second.interfaces.contains { $0.name == "eth0" }, "iface eth0")
    try expect(second.primaryDisk?.mount == "/", "primary disk")
}

func inspectDetailChecks() throws {
    var parser = LinuxMetricsParser()
    let first = try parser.consume(
        detailSample(rx: 1_000, tx: 2_000, readSectors: 1_000, writeSectors: 2_000, readOps: 10, writeOps: 20),
        at: Date(timeIntervalSince1970: 20)
    )
    try expect(first.interfaces.contains { $0.name == "eth0" && $0.ipv4CIDR == "10.2.0.8/24" }, "cidr")
    try expect(first.disks.contains { $0.mount == "/" && $0.fstype == "ext4" }, "fstype")
    try expect(first.disks.contains { $0.mount == "/boot" && $0.filesystem == "/dev/sda16" }, "boot disk")
    guard let root = first.disks.first(where: { $0.mount == "/" }) else {
        throw CheckFailure.message("root missing")
    }
    try expect(root.readBytes == 1_000 * 512, "root read bytes \(root.readBytes)")
    try expect(root.readBytesPerSecond == nil, "first root rate")

    let second = try parser.consume(
        detailSample(rx: 3_000, tx: 6_000, readSectors: 1_400, writeSectors: 2_800, readOps: 20, writeOps: 40),
        at: Date(timeIntervalSince1970: 22)
    )
    guard let root2 = second.disks.first(where: { $0.mount == "/" }) else {
        throw CheckFailure.message("second root missing")
    }
    try expect(abs((root2.readBytesPerSecond ?? -1) - 102_400) < 0.1, "root read rate \(String(describing: root2.readBytesPerSecond))")
    try expect(abs((root2.writeBytesPerSecond ?? -1) - 204_800) < 0.1, "root write rate")
    try expect(abs((root2.readIOPS ?? -1) - 5) < 0.1, "root read iops \(String(describing: root2.readIOPS))")
    try expect(second.primaryDisk?.fstype == "ext4", "primary fstype")
}

func inspectMetricChecks() throws {
    var parser = LinuxMetricsParser()
    let first = try parser.consume(inspectSample(rx: 1_000, tx: 2_000, dockerRx: "1kB", dockerTx: "2kB"), at: Date(timeIntervalSince1970: 10))
    try expect(first.cpuModel.contains("Test CPU"), "cpu model")
    try expect(first.osPrettyName.contains("Ubuntu"), "os pretty")
    try expect(first.osID == "ubuntu", "os id")
    try expect(first.osDisplayName.contains("Ubuntu"), "os display")
    try expect(first.cpuUsage == nil, "first usage")
    try expect(first.containers.count == 1 && first.containers[0].name == "web", "docker name")
    try expect(first.containers[0].status.contains("healthy"), "docker status")
    try expect(first.containers[0].netReceiveBytesPerSecond == nil, "first docker rate")
    try expect(first.memoryFreeBytes == 400 * 1024, "mem free")
    try expect(abs(parsePercentRatio("12.5%") - 0.125) < 0.0001, "percent")
    try expect(parseDataSize("1.5GiB") == UInt64(1.5 * 1024 * 1024 * 1024), "gib")
    try expect(parseDataSize("847MB") == 847_000_000, "mb")

    let second = try parser.consume(
        inspectSample(rx: 3_000, tx: 6_000, dockerRx: "3kB", dockerTx: "6kB"),
        at: Date(timeIntervalSince1970: 12)
    )
    try expect(second.cores.count == 2, "two cores")
    try expect(second.cpuUsage == nil || (second.cpuUsage ?? 1) >= 0, "cpu usage present or nil")
    guard let docker = second.containers.first else { throw CheckFailure.message("docker missing") }
    try expect(abs((docker.netReceiveBytesPerSecond ?? -1) - 1_000) < 0.1, "docker rx \(String(describing: docker.netReceiveBytesPerSecond))")
    try expect(abs((docker.netTransmitBytesPerSecond ?? -1) - 2_000) < 0.1, "docker tx")
}

func storageSelectionChecks() throws {
    var parser = LinuxMetricsParser()
    let firstText = """
    HP_BEGIN
    os=Linux
    hostname=syno
    uptime_sec=10
    cpu_cores=2
    cpu_model=Test
    HP_STAT
    cpu  0 0 0 0 0 0 0 0
    HP_MEM
    MemTotal: 100 kB
    MemAvailable: 40 kB
    SwapTotal: 0 kB
    SwapFree: 0 kB
    HP_NET
    eth0: 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
    HP_DISK
    Filesystem Type 1B-blocks Used Available Capacity Mounted on
    /dev/md0 ext4 8387944448 1933516800 6332792832 24% /
    /dev/mapper/cachedev_0 btrfs 939051651072 173324832768 765726818304 19% /volume2
    /dev/mapper/cachedev_1 btrfs 15349525921792 8463040823296 6886485098496 56% /volume1
    nas.example:/share nfs 9999999999999 1 9999999999998 1% /mnt/nfs
    HP_DISKIO
       8       0 sda 1 0 1000 0 2 0 2000 0 0 0 0
       8       1 sda1 1 0 1000 0 2 0 2000 0 0 0 0
     259       0 synoboot 1 0 999999 0 2 0 999999 0 0 0 0
     259       1 synoboot1 1 0 999999 0 2 0 999999 0 0 0 0
       9       2 md2 1 0 5000 0 2 0 5000 0 0 0 0
     253       1 dm-1 1 0 5000 0 2 0 5000 0 0 0 0
    HP_END
    """
    _ = try parser.consume(firstText, at: Date(timeIntervalSince1970: 10))
    let secondText = firstText
        .replacingOccurrences(of: "0 sda 1 0 1000", with: "0 sda 1 0 1400")
        .replacingOccurrences(of: "0 synoboot 1 0 999999", with: "0 synoboot 1 0 1999999")
        .replacingOccurrences(of: "1 synoboot1 1 0 999999", with: "1 synoboot1 1 0 1999999")
    let second = try parser.consume(secondText, at: Date(timeIntervalSince1970: 12))
    try expect(
        second.primaryDisk?.mount == "/volume1",
        "primary is data volume not root \(second.primaryDisk?.mount ?? "nil")"
    )
    let expectedTotal: UInt64 = 8_387_944_448 + 939_051_651_072 + 15_349_525_921_792
    try expect(second.localStorageBytes == expectedTotal, "local storage \(second.localStorageBytes)")
    try expect(!second.localDisks.contains { $0.mount == "/mnt/nfs" }, "nfs excluded")
    try expect(
        abs((second.diskReadBytesPerSecond ?? -1) - 102_400) < 0.1,
        "host disk read ignores synoboot/md/dm \(String(describing: second.diskReadBytesPerSecond))"
    )
}

func configChecks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try """
    Host extra-box
      HostName extra.example.test
      User deploy
      Port 2222
    """.write(to: directory.appendingPathComponent("extra"), atomically: true, encoding: .utf8)

    let config = directory.appendingPathComponent("config")
    try """
    Host *
      Port 22
      User fallback
    Host jp01
      User ubuntu
    Host *.internal
      User nobody
    Include extra
    Host jump-only
      HostName jump.example.test
      IdentityFile \(directory.path)/id_ed25519
    """.write(to: config, atomically: true, encoding: .utf8)
    try Data("dummy".utf8).write(to: directory.appendingPathComponent("id_ed25519"))

    let hosts = try SSHConfigImporter().importHosts(configURL: config)
    let names = Set(hosts.map(\.name))
    try expect(names.contains("jp01"), "jp01 imported")
    try expect(names.contains("extra-box"), "include imported")
    try expect(names.contains("jump-only"), "jump imported")
    try expect(!names.contains("*") && !names.contains("*.internal"), "patterns skipped")
    let jp01 = hosts.first { $0.name == "jp01" }!
    try expect(jp01.username == "ubuntu" && jp01.authKind == .agent, "jp01 fields")
    let extra = hosts.first { $0.name == "extra-box" }!
    try expect(extra.port == 2222 && extra.hostname == "extra.example.test", "extra fields")
    let jump = hosts.first { $0.name == "jump-only" }!
    try expect(jump.authKind == .privateKey, "jump key auth")
}

func sshConfigUsernameFillChecks() throws {
    let mac = "jim"
    try expect(
        SSHConfigImporter.usernameToApply(current: "jim", fromConfig: "ubuntu", macUsername: mac) == "ubuntu",
        "replace mac default with config user"
    )
    try expect(
        SSHConfigImporter.usernameToApply(current: "", fromConfig: "ubuntu", macUsername: mac) == "ubuntu",
        "replace empty"
    )
    try expect(
        SSHConfigImporter.usernameToApply(current: "root", fromConfig: "ubuntu", macUsername: mac) == nil,
        "keep typed username"
    )
    try expect(
        SSHConfigImporter.usernameToApply(
            current: "ubuntu",
            fromConfig: "root",
            macUsername: mac,
            lastAutoFilled: "ubuntu"
        ) == "root",
        "follow alias change after autofill"
    )
    try expect(
        SSHConfigImporter.usernameToApply(current: "ubuntu", fromConfig: "ubuntu", macUsername: mac) == nil,
        "no change when already matching"
    )
    try expect(
        SSHConfigImporter.usernameToApply(current: "jim", fromConfig: "jim", macUsername: mac) == nil,
        "mac user matches config"
    )
}

func sample(
    idle: UInt64,
    totalIdleAndBusy: UInt64,
    rx: UInt64,
    tx: UInt64,
    readSectors: UInt64 = 1_000,
    writeSectors: UInt64 = 2_000,
    extra: String = ""
) -> String {
    let busy = totalIdleAndBusy - idle
    return """
    HP_BEGIN
    os=Linux
    os_pretty=Ubuntu 24.04.4 LTS (Noble Numbat)
    os_id=ubuntu
    hostname=jp01
    uptime_sec=3600
    loadavg=0.10 0.20 0.30
    cpu_cores=2
    cpu_model=Test CPU (x86_64)
    HP_STAT
    cpu  \(busy) 0 0 \(idle) 0 0 0 0
    cpu0 \(busy) 0 0 \(idle) 0 0 0 0
    cpu1 \(busy) 0 0 \(idle) 0 0 0 0
    HP_MEM
    MemTotal:       2000 kB
    MemAvailable:    500 kB
    MemFree:         400 kB
    Cached:          100 kB
    Buffers:           0 kB
    SwapTotal:         0 kB
    SwapFree:          0 kB
    HP_NET
    eth0: \(rx) 0 0 0 0 0 0 0 \(tx) 0 0 0 0 0 0 0
    lo: 50 0 0 0 0 0 0 0 50 0 0 0 0 0 0 0
    HP_DISK
    Filesystem     1B-blocks        Used   Available Capacity Mounted on
    /dev/sda1        1000000      400000      600000      40% /
    tmpfs               9999         100        9899       1% /run
    HP_DISKIO
       8       0 sda 1 0 \(readSectors) 0 2 0 \(writeSectors) 0 0 0 0
       8       1 sda1 1 0 999999 0 2 0 999999 0 0 0 0
       7       0 loop0 0 0 0 0 0 0 0 0 0 0 0
    HP_PROC
      1 root 0.1 0.2 1024 systemd
     42 ubuntu 3.5 1.0 4096 sshd
    \(extra)HP_END
    """
}

func detailSample(
    rx: UInt64,
    tx: UInt64,
    readSectors: UInt64,
    writeSectors: UInt64,
    readOps: UInt64,
    writeOps: UInt64
) -> String {
    """
    HP_BEGIN
    os=Linux
    hostname=jp01
    uptime_sec=3600
    loadavg=0.10 0.20 0.30
    cpu_cores=2
    cpu_model=Test CPU (x86_64)
    HP_STAT
    cpu  100 0 0 100 0 0 0 0
    cpu0 100 0 0 100 0 0 0 0
    cpu1 100 0 0 100 0 0 0 0
    HP_MEM
    MemTotal:       2000 kB
    MemAvailable:    500 kB
    MemFree:         400 kB
    Cached:          100 kB
    Buffers:           0 kB
    SwapTotal:         0 kB
    SwapFree:          0 kB
    HP_NET
    eth0: \(rx) 0 0 0 0 0 0 0 \(tx) 0 0 0 0 0 0 0
    lo: 50 0 0 0 0 0 0 0 50 0 0 0 0 0 0 0
    HP_ADDR
    2: eth0    inet 10.2.0.8/24 brd 10.2.0.255 scope global eth0
    HP_DISK
    Filesystem Type 1B-blocks Used Available Capacity Mounted on
    /dev/sda1 ext4 1000000 400000 600000 40% /
    /dev/sda16 ext4 200000 50000 150000 25% /boot
    tmpfs tmpfs 9999 100 9899 1% /run
    HP_DISKIO
       8       0 sda 1 0 \(readSectors) 0 2 0 \(writeSectors) 0 0 0 0
       8       1 sda1 \(readOps) 0 \(readSectors) \(readOps * 2) \(writeOps) 0 \(writeSectors) \(writeOps * 2) 0 0 0
       8      16 sda16 1 0 100 0 1 0 200 0 0 0 0
    HP_PROC
      1 root 0.1 0.2 1024 systemd
    HP_END
    """
}

func inspectSample(rx: UInt64, tx: UInt64, dockerRx: String, dockerTx: String) -> String {
    sample(
        idle: 100,
        totalIdleAndBusy: 200,
        rx: rx,
        tx: tx,
        extra: """
        HP_DOCKER
        web|1.50%|10.00%|100MiB / 1GiB|\(dockerRx) / \(dockerTx)|0B / 0B
        HP_DOCKERPS
        web|Up 2 days (healthy)
        """
    )
}

func hostRecordCodableChecks() throws {
    let json = """
    [{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","name":"jp01","hostname":"jp01","port":22,"username":"ubuntu","authKind":"agent","createdAt":0}]
    """
    let hosts = try JSONDecoder().decode([HostRecord].self, from: Data(json.utf8))
    try expect(hosts.count == 1, "one host")
    try expect(hosts[0].showOnDashboard, "dashboard default true")
    try expect(hosts[0].defaultSFTPPath == "/", "sftp default")
    try expect(hosts[0].tags.isEmpty, "tags default")
    try expect(hosts[0].notes.isEmpty, "notes default")
    try expect(hosts[0].group == nil, "group default")
    try expect(hosts[0].connectionKind == .ssh, "ssh default")
    try expect(hosts[0].sshKeyFingerprint == nil, "fingerprint default")

    var record = hosts[0]
    record.group = " oracle "
    record.tags = ["lab", " Lab ", "", "tokyo"]
    record.notes = "ampere"
    record.showOnDashboard = false
    record.defaultSFTPPath = "  /home/ubuntu  "
    record = HostRecord(
        id: record.id,
        name: record.name,
        hostname: record.hostname,
        port: record.port,
        username: record.username,
        authKind: record.authKind,
        privateKeyPath: record.privateKeyPath,
        createdAt: record.createdAt,
        connectionKind: record.connectionKind,
        group: record.group,
        tags: record.tags,
        notes: record.notes,
        showOnDashboard: record.showOnDashboard,
        defaultSFTPPath: record.defaultSFTPPath
    )
    try expect(record.group == "oracle", "group trim")
    try expect(record.tags == ["lab", "tokyo"], "tags unique")
    try expect(record.defaultSFTPPath == "/home/ubuntu", "sftp trim")

    let encoded = try JSONEncoder().encode([record])
    let round = try JSONDecoder().decode([HostRecord].self, from: encoded)
    try expect(round[0].group == "oracle", "group roundtrip")
    try expect(round[0].tags == ["lab", "tokyo"], "tags roundtrip")
    try expect(round[0].notes == "ampere", "notes roundtrip")
    try expect(round[0].showOnDashboard == false, "dashboard roundtrip")
    try expect(round[0].defaultSFTPPath == "/home/ubuntu", "sftp roundtrip")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HostStore(fileURL: directory.appendingPathComponent("hosts.json"))
    try store.save([record])
    let loaded = try store.load()
    try expect(loaded[0].group == "oracle" && loaded[0].tags == ["lab", "tokyo"], "store roundtrip")
}

func keyFingerprintChecks() throws {
    let blob = Data(repeating: 7, count: 32).base64EncodedString()
    let line = "ssh-ed25519 \(blob) comment-here"
    guard let parsed = SSHKeyFile.parsePublicKeyLine(line) else {
        throw CheckFailure.message("public key parse failed")
    }
    try expect(parsed.type == "ssh-ed25519", "key type")
    try expect(parsed.comment == "comment-here", "key comment")
    try expect(parsed.fingerprint.hasPrefix("SHA256:"), "fingerprint prefix")

    let records = SSHKeyFile.records(
        fromPublicKeyText: "\(line)\n# skip\nssh-ed25519 not-valid\n",
        origin: .clipboard
    )
    try expect(records.count == 1, "clipboard one key")
    try expect(records[0].origin == .clipboard, "clipboard origin")
    try expect(records[0].privateKeyPath.isEmpty, "no private path")
    try expect(records[0].shortType == "ED25519", "short type")
    try expect(SSHKeyFile.looksLikePublicKey(line), "looks like pubkey")

    let json = """
    [{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","name":"agent-key","privateKeyPath":"","keyType":"ssh-ed25519","fingerprint":"SHA256:abc","comment":"1p","createdAt":0}]
    """
    let decoded = try JSONDecoder().decode([SSHKeyRecord].self, from: Data(json.utf8))
    try expect(decoded[0].origin == .clipboard, "legacy empty path origin")
    try expect(decoded[0].publicKey.isEmpty, "public key default")
}

func latencyWindowChecks() throws {
    var window = LatencyWindow(capacity: 5)
    try expect(window.medianSeconds == nil, "empty median")
    window.push(2.4)
    window.push(0.20)
    window.push(0.22)
    window.push(0.18)
    window.push(0.25)
    window.push(9.9)
    guard let median = window.medianSeconds else { throw CheckFailure.message("median missing") }
    try expect(abs(median - 0.22) < 0.0001, "median \(median)")
    window.push(20)
    guard let still = window.medianSeconds else { throw CheckFailure.message("ignored outlier") }
    try expect(abs(still - 0.22) < 0.0001, "outlier ignored \(still)")
    try expect(abs(durationToSeconds(.milliseconds(250)) - 0.25) < 0.0001, "duration")
}

func settingsCodableChecks() throws {
    let empty = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    try expect(empty.connectionTimeoutSeconds == 15, "timeout default")
    try expect(empty.alwaysTrustHostKeys == false, "trust default")
    try expect(empty.terminalBellEnabled, "bell default")
    try expect(empty.terminalKeepAlive, "keepalive default")
    try expect(empty.terminalKeepAliveSeconds == 10, "keepalive interval")
    try expect(empty.sftpKeepAlive, "sftp keepalive default")
    try expect(empty.textFileOpener == .builtIn, "opener default")
    try expect(empty.appearance == .system, "appearance default")
    try expect(empty.dashboardHostIDs.isEmpty, "dashboard order default")
    try expect(empty.sessionToolbarMode == .iconAndText, "toolbar mode default")
    try expect(empty.terminalFontSize == 13, "font size default")
    try expect(empty.terminalCursorBlink, "cursor blink default")
    try expect(empty.terminalScrollbar == .overlay, "scrollbar default")
    try expect(empty.appLoggingEnabled, "logging default")

    var settings = AppSettings(connectionTimeoutSeconds: 3, terminalKeepAliveSeconds: 999)
    try expect(settings.connectionTimeoutSeconds == 5, "timeout clamp low")
    try expect(settings.terminalKeepAliveSeconds == 120, "keepalive clamp high")
    settings.alwaysTrustHostKeys = true
    settings.suggestPortForward = true
    settings.sftpKeepAlive = true
    settings.textFileOpener = .defaultApp
    settings.appearance = .dark

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
    try store.save(settings)
    let loaded = try store.load()
    try expect(loaded.alwaysTrustHostKeys, "trust roundtrip")
    try expect(loaded.suggestPortForward, "forward roundtrip")
    try expect(loaded.textFileOpener == .defaultApp, "opener roundtrip")
    try expect(loaded.sftpKeepAlive, "sftp keepalive roundtrip")
    try expect(loaded.appearance == .dark, "appearance roundtrip")

    let first = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let second = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
    settings.dashboardHostIDs = [second, first]
    try store.save(settings)
    let ordered = try store.load()
    try expect(ordered.dashboardHostIDs == [second, first], "dashboard order roundtrip")
}

func dashboardPreferenceChecks() throws {
    let empty = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    try expect(empty.dashboardBackgroundLight == .plain, "background light default")
    try expect(empty.dashboardBackgroundDark == .plain, "background dark default")
    try expect(empty.statusRefreshSeconds == 5, "status refresh default")
    try expect(empty.showTagFilter, "tag filter default")
    try expect(empty.showTagsOnMachines, "machine tags default")
    try expect(empty.showLatency, "latency default")
    try expect(empty.latencyUsesColor, "latency color default")
    try expect(empty.latencyRefreshSeconds == 30, "latency interval default")
    try expect(empty.reduceStatusMotion == false, "motion default")
    try expect(empty.statusLayout == .default, "layout default")

    var settings = AppSettings(statusRefreshSeconds: 1, latencyRefreshSeconds: 4)
    try expect(settings.statusRefreshSeconds == 2, "status refresh clamp")
    try expect(settings.latencyRefreshSeconds == 5, "latency interval clamp")
    settings = AppSettings(statusRefreshSeconds: 8)
    try expect(settings.statusRefreshSeconds == 10, "status refresh nearest")

    let slots = StatusLayoutGrid.slots(for: .default)
    let cpu = slots.first { $0.kind == .cpu }
    try expect(cpu?.row == 0 && cpu?.column == 0 && cpu?.width == 2, "cpu slot")
    let load = slots.first { $0.kind == .load }
    try expect(load?.row == 1 && load?.column == 0, "load slot")
    let processes = slots.first { $0.kind == .processes }
    try expect(processes?.row == 1 && processes?.column == 1 && processes?.height == 2, "process slot")
    let memory = slots.first { $0.kind == .memory }
    try expect(memory?.row == 2 && memory?.column == 0, "memory slot")
    let network = slots.first { $0.kind == .network }
    try expect(network?.row == 3 && network?.width == 2, "network slot")

    var layout = StatusDetailLayout.default
    layout.remove(.docker)
    layout.columns = 9
    let normalized = layout.normalized()
    try expect(normalized.columns == 4, "column clamp")
    try expect(normalized.missingKinds == [.docker], "missing docker")
    settings.dashboardBackgroundLight = .ocean
    settings.dashboardBackgroundDark = .neon
    settings.showTagFilter = false
    settings.showTagsOnMachines = false
    settings.showLatency = false
    settings.latencyUsesColor = false
    settings.reduceStatusMotion = true
    settings.statusLayout = normalized

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
    try store.save(settings)
    let loaded = try store.load()
    try expect(loaded.dashboardBackgroundLight == .ocean, "background light roundtrip")
    try expect(loaded.dashboardBackgroundDark == .neon, "background dark roundtrip")
    try expect(loaded.showTagFilter == false, "tag filter roundtrip")
    try expect(loaded.showTagsOnMachines == false, "machine tags roundtrip")
    try expect(loaded.showLatency == false, "latency roundtrip")
    try expect(loaded.latencyUsesColor == false, "latency color roundtrip")
    try expect(loaded.reduceStatusMotion, "motion roundtrip")
    try expect(loaded.statusLayout.columns == 4, "layout columns roundtrip")
    try expect(!loaded.statusLayout.cards.contains { $0.kind == .docker }, "layout cards roundtrip")
}

func configSyncChecks() throws {
    try expect(ConfigSync.syncedFileNames.contains("hosts.json"), "hosts file")
    try expect(ConfigSync.syncedFileNames.contains("settings.json"), "settings file")
    try expect(ConfigSync.statusText(for: .local) == "同步未开始", "local status")
    if ConfigSync.dropboxRoot() != nil {
        let url = try ConfigSync.directory(for: .dropbox)
        try expect(url.lastPathComponent == "Hostpane", "dropbox folder name")
        try expect(
            url.deletingLastPathComponent().lastPathComponent == "Apps",
            "dropbox lives under Apps \(url.path)"
        )
    }

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("hostpane-sync-\(UUID().uuidString)")
    let source = root.appendingPathComponent("source")
    let dest = root.appendingPathComponent("dest")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    switch ConfigSync.plan(from: source, to: dest) {
    case .switchOnly:
        break
    default:
        throw CheckFailure.message("empty to empty should switchOnly")
    }

    let alpha = HostRecord(name: "alpha", hostname: "alpha.example", username: "ubuntu")
    try HostStore(fileURL: source.appendingPathComponent("hosts.json")).save([alpha])
    switch ConfigSync.plan(from: source, to: dest) {
    case .seedEmptyDestination:
        break
    default:
        throw CheckFailure.message("source data into empty dest should seed")
    }
    try ConfigSync.execute(from: source, to: dest, choice: nil)
    let seeded = try HostStore(fileURL: dest.appendingPathComponent("hosts.json")).load()
    try expect(seeded.count == 1 && seeded[0].name == "alpha", "seeded host")

    let emptySource = root.appendingPathComponent("empty-source")
    try FileManager.default.createDirectory(at: emptySource, withIntermediateDirectories: true)
    switch ConfigSync.plan(from: emptySource, to: dest) {
    case .switchOnly:
        break
    default:
        throw CheckFailure.message("empty source must not overwrite dest")
    }
    try ConfigSync.execute(from: emptySource, to: dest, choice: nil)
    let preserved = try HostStore(fileURL: dest.appendingPathComponent("hosts.json")).load()
    try expect(preserved.count == 1 && preserved[0].name == "alpha", "dest preserved")

    let beta = HostRecord(name: "beta", hostname: "beta.example", username: "ubuntu")
    try HostStore(fileURL: emptySource.appendingPathComponent("hosts.json")).save([beta])
    try SettingsStore(fileURL: dest.appendingPathComponent("settings.json")).save(AppSettings(appearance: .dark))
    switch ConfigSync.plan(from: emptySource, to: dest) {
    case .confirm(let sourceInventory, let destinationInventory):
        try expect(sourceInventory.hostCount == 1, "confirm source hosts")
        try expect(destinationInventory.hostCount == 1, "confirm dest hosts")
        try expect(destinationInventory.hasSettings, "confirm dest settings")
    default:
        throw CheckFailure.message("different data should confirm")
    }

    do {
        try ConfigSync.execute(from: emptySource, to: dest, choice: nil)
        throw CheckFailure.message("confirm without choice should throw")
    } catch ConfigSyncError.confirmationRequired {
        ()
    } catch {
        throw CheckFailure.message("wrong error \(error)")
    }

    try ConfigSync.execute(from: emptySource, to: dest, choice: .keepDestination)
    let kept = try HostStore(fileURL: dest.appendingPathComponent("hosts.json")).load()
    try expect(kept[0].name == "alpha", "keep dest hosts")
    let keptSettings = try SettingsStore(fileURL: dest.appendingPathComponent("settings.json")).load()
    try expect(keptSettings.appearance == .dark, "keep dest settings")

    try ConfigSync.execute(from: emptySource, to: dest, choice: .keepSource)
    let overwritten = try HostStore(fileURL: dest.appendingPathComponent("hosts.json")).load()
    try expect(overwritten[0].name == "beta", "keep source hosts")
    try expect(
        !FileManager.default.fileExists(atPath: dest.appendingPathComponent("settings.json").path),
        "keep source removes dest-only files"
    )

    let clone = root.appendingPathComponent("clone")
    try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)
    try ConfigSync.execute(from: dest, to: clone, choice: nil)
    switch ConfigSync.plan(from: dest, to: clone) {
    case .switchOnly:
        break
    default:
        throw CheckFailure.message("equivalent files should switchOnly")
    }

    let conflictName = "hosts.json (Air 的冲突副本 2026-09-16)"
    try Data("x".utf8).write(to: dest.appendingPathComponent(conflictName))
    let names = ConfigSync.conflictCopyNames(in: dest)
    try expect(names.contains(conflictName), "conflict copy detected")

    let rebound = HostStore()
    try expect(
        rebound.fileURL.lastPathComponent == "hosts.json",
        "default host store still resolves hosts.json"
    )
    try expect(
        rebound.fileURL.deletingLastPathComponent().path == HostStore.applicationSupportDirectory().path,
        "default host store follows active directory"
    )
}

func metricBandChecks() throws {
    try expect(MetricBand.latency(0.02) == .low, "lan latency")
    try expect(MetricBand.latency(0.12) == .medium, "wan latency")
    try expect(MetricBand.latency(0.40) == .high, "high latency")
    try expect(MetricBand.usage(0.25) == .low, "low load")
    try expect(MetricBand.usage(0.72) == .medium, "mid load")
    try expect(MetricBand.usage(0.92) == .high, "high load")
}

func sftpPathChecks() throws {
    try expect(SFTPPaths.normalize("/home/ubuntu/../root//.ssh") == "/home/root/.ssh", "normalize")
    try expect(SFTPPaths.join("/", "etc") == "/etc", "join root")
    try expect(SFTPPaths.join("/home/ubuntu", "src") == "/home/ubuntu/src", "join")
    try expect(SFTPPaths.join("/home/ubuntu", "..") == "/home", "join parent")
    try expect(SFTPPaths.parent("/") == "/", "parent root")
    try expect(SFTPPaths.parent("/home") == "/", "parent home")
    try expect(SFTPPaths.kind(permissions: 0o40755, longName: "") == .directory, "dir bits")
    try expect(SFTPPaths.kind(permissions: 0o100644, longName: "") == .file, "file bits")
    try expect(SFTPPaths.kind(permissions: nil, longName: "lrwxrwxrwx") == .symbolicLink, "link longname")
    try expect(SFTPPaths.isProbablyText("notes.md"), "markdown")
    try expect(!SFTPPaths.isProbablyText("photo.png"), "png")
    try expect(SFTPPaths.isHiddenName(".bashrc"), "dotfile")
    try expect(!SFTPPaths.isHiddenName("bin"), "visible")
}

func dashboardOrderChecks() throws {
    let a = HostRecord(name: "a", hostname: "a.example", username: "u")
    let b = HostRecord(name: "b", hostname: "b.example", username: "u")
    let c = HostRecord(name: "c", hostname: "c.example", username: "u")
    let unsorted = [a, b, c]
    try expect(DashboardHostOrder.sorted(unsorted, by: []).map(\.name) == ["a", "b", "c"], "empty order")
    try expect(
        DashboardHostOrder.sorted(unsorted, by: [c.id, a.id]).map(\.name) == ["c", "a", "b"],
        "explicit then leftover"
    )
    try expect(
        DashboardHostOrder.sorted(unsorted, by: [b.id]).map(\.name) == ["b", "a", "c"],
        "single pinned"
    )
}

func dockerParserChecks() throws {
    let detect = """
    HP_BEGIN
    docker_bin=/usr/bin/docker
    context=default
    socket=/var/run/docker.sock
    socket_writable=/var/run/docker.sock
    HP_VERSION
    29.7.2|1.55|linux|amd64
    HP_INFO
    Ubuntu 24.04.4 LTS|x86_64|2|1000000000
    HP_END
    """
    let engine = try DockerParser().parseDetect(detect)
    try expect(engine.version == "29.7.2", "engine version")
    try expect(engine.apiVersion == "1.55", "api")
    try expect(engine.socket == "/var/run/docker.sock", "socket")
    try expect(engine.socketWritable, "writable")

    let snapshotText = """
    HP_BEGIN
    docker_bin=/usr/bin/docker
    context=default
    socket=/var/run/docker.sock
    socket_writable=/var/run/docker.sock
    HP_VERSION
    29.7.2|1.55|linux|amd64
    HP_INFO
    Ubuntu 24.04.4 LTS|x86_64|2|1000000000
    HP_DF
    Images|35|10|16.5GB|6.24GB (37%)
    Containers|9|7|1.95MB|0B (0%)
    Local Volumes|4|2|114MB|0B
    Build Cache|12|0|480MB|480MB
    HP_PS
    abc123|gitlab-runner|gitlab/gitlab-runner:latest|running|Up 3 hours|
    def456|ss-server-10086|ss:latest|exited|Exited (0) 2 hours ago|
    HP_STATS
    gitlab-runner|131.6%|12.00%|34.4MiB / 954MiB|1B / 1B|1B / 1B
    HP_IMAGES
    sha256:1|ubuntu|24.04|80MB|3 days ago
    HP_VOLUMES
    data|local|/var/lib/docker/volumes/data
    HP_NETWORKS
    net1|bridge|bridge|local
    HP_COMPOSE
    demo|running(2)|/opt/demo/compose.yml
    HP_EVENTS
    1710000000|container|start|gitlab-runner
    HP_END
    """
    let snapshot = try DockerParser().parseSnapshot(snapshotText)
    try expect(snapshot.runningCount == 1, "running")
    try expect(snapshot.stoppedCount == 1, "stopped")
    try expect(snapshot.images.count == 1, "images")
    try expect(snapshot.disk.images.count == 35, "df images")
    try expect(abs((snapshot.disk.images.reclaimablePercent ?? 0) - 0.37) < 0.01, "reclaimable percent")
    try expect((snapshot.containers.first?.cpuRatio ?? 0) > 1, "cpu uncapped")
    try expect(parseDockerSize("6.24GB (37%)") == 6_240_000_000, "docker size paren")

    let inspectText = """
    HP_BEGIN
    docker_bin=/usr/bin/docker
    HP_VERSION
    29.7.2|1.55|linux|amd64
    HP_PS
    c6b7311376e3|beszel-agent|henrygd/beszel-agent:0.19.0|running|Up 9 hours (healthy)|
    HP_INSPECT
    [{"Id":"c6b7311376e3abcdef","Name":"/beszel-agent","Created":"2026-09-15T07:41:00Z","Config":{"Image":"henrygd/beszel-agent:0.19.0","Cmd":["/agent"],"Env":["FOO=1","BAR=2"],"Labels":{"com.docker.compose.project":"beszel","com.docker.compose.service":"beszel-agent-jp01"}},"State":{"Status":"running","Pid":10,"Health":{"Status":"healthy"}},"HostConfig":{"RestartPolicy":{"Name":"unless-stopped"},"NetworkMode":"host"},"Mounts":[{"Source":"/etc/machine-id","Destination":"/etc/machine-id","RW":false,"Type":"bind"}]}]
    HP_END
    """
    let inspected = try DockerParser().parseSnapshot(inspectText)
    let agent = inspected.containers[0]
    try expect(agent.isHealthy, "healthy")
    try expect(agent.composeProject == "beszel", "compose project")
    try expect(agent.command == "/agent", "command")
    try expect(agent.mounts.count == 1 && agent.mounts[0].readOnly, "ro mount")
    try expect(agent.pid == 10, "pid")

    let fast = try DockerParser().parseSnapshot("""
    HP_BEGIN
    HP_PS
    abc123|gitlab-runner|gitlab/gitlab-runner:latest|running|Up 3 hours (healthy)|0.0.0.0:8080->80/tcp|2026-09-15 15:41:00 +0800 CST|com.docker.compose.project=demo,com.docker.compose.service=runner
    HP_END
    """)
    try expect(fast.engine.version.isEmpty, "fast snapshot has no engine")
    try expect(fast.containers.count == 1, "fast ps")
    try expect(fast.containers[0].isHealthy, "health from status")
    try expect(fast.containers[0].composeProject == "demo", "compose from labels")

    let images = try DockerParser().parseSnapshot("""
    HP_BEGIN
    HP_IMAGES
    00c88600e7d1|henrygd/beszel-agent|0.19.0|13.8MB|2 weeks ago|sha256:00c88600e7d1deadbeef
    1ca4906c0d96|<none>|<none>|342MB|4 weeks ago|<none>
    HP_PS
    abc|beszel-agent|henrygd/beszel-agent:0.19.0|running|Up 9 hours (healthy)|
    HP_END
    """)
    try expect(images.images.count == 2, "two images")
    try expect(images.images[0].displayName == "henrygd/beszel-agent:0.19.0", "named image")
    try expect(images.images[1].isDangling, "dangling")
    try expect(images.images[1].displayName == "<无>", "dangling title")
    try expect(images.images[0].usedBy(images.containers).count == 1, "image in use")
    try expect(images.images[1].usedBy(images.containers).isEmpty, "dangling unused")

    let volumes = try DockerParser().parseSnapshot("""
    HP_BEGIN
    HP_PS
    abc|boinc|img|running|Up 1 hour|||com.docker.compose.project=boinc|boinc_boinc-data-jp01
    HP_VOLUMES
    boinc_boinc-data-jp01|local|/var/lib/docker/volumes/boinc_boinc-data-jp01/_data
    orphan|local|/var/lib/docker/volumes/orphan/_data
    HP_END
    """)
    try expect(volumes.volumes.count == 2, "two volumes")
    try expect(volumes.volumes[0].usedBy(volumes.containers).count == 1, "volume in use")
    try expect(volumes.volumes[1].usedBy(volumes.containers).isEmpty, "volume unused")

    let nets = try DockerParser().parseSnapshot("""
    HP_BEGIN
    HP_PS
    a|beszel-agent|img|running|Up 1 hour|||||host
    b|web|img|running|Up 1 hour|||||ss-server_default
    HP_NETWORKS
    16091f898ba6|ss-server_default|bridge|local
    a7fd52949439|host|host|local
    HP_NETINSPECT
    [{"Name":"ss-server_default","Id":"16091f898ba6abcd","Driver":"bridge","Scope":"local","IPAM":{"Config":[{"Subnet":"172.18.0.0/16","Gateway":"172.18.0.1"}]}},{"Name":"host","Id":"a7fd52949439abcd","Driver":"host","Scope":"local","IPAM":{"Config":null}}]
    HP_END
    """)
    try expect(nets.networks.count == 2, "two networks")
    try expect(nets.networks[0].subnet == "172.18.0.0/16", "subnet")
    try expect(nets.networks[0].gateway == "172.18.0.1", "gateway")
    try expect(nets.networks[1].isBuiltin, "host builtin")
    try expect(nets.networks[1].usedBy(nets.containers).count == 1, "host users")
    try expect(nets.networks[0].usedBy(nets.containers).count == 1, "custom users")

    let events = try DockerParser().parseSnapshot("""
    HP_BEGIN
    HP_EVENTS
    {"Type":"container","Action":"exec_die","Actor":{"Attributes":{"image":"ss-server-ss-server-10000","name":"ss-server-10000"}},"time":1710000000}
    {"Type":"container","Action":"exec_start: /bin/sh -c nc -z 127.0.0.1 10000","Actor":{"Attributes":{"image":"ss-server-ss-server-10000","name":"ss-server-10000"}},"time":1710000001}
    HP_END
    """)
    try expect(events.events.count == 2, "two events")
    try expect(events.events[0].title == "exec_die ss-server-10000", "exec_die title")
    try expect(events.events[0].image.contains("ss-server"), "image")
    try expect(events.events[1].action.contains("nc -z"), "exec_start command")
}

do {
    try metricsChecks()
    try latencyWindowChecks()
    try inspectMetricChecks()
    try inspectDetailChecks()
    try storageSelectionChecks()
    try configChecks()
    try sshConfigUsernameFillChecks()
    try hostRecordCodableChecks()
    try settingsCodableChecks()
    try dashboardPreferenceChecks()
    try dashboardOrderChecks()
    try sftpPathChecks()
    try metricBandChecks()
    try configSyncChecks()
    try keyFingerprintChecks()
    try dockerParserChecks()
    print("HostpaneCheck passed")
} catch {
    fputs("HostpaneCheck failed: \(error)\n", stderr)
    exit(1)
}
