import AppKit
import Foundation
import Observation
import HostpaneCore
import Traversio

enum DashboardReachability: Equatable, Sendable {
    case connecting
    case online
    case offline
}

enum ConnectionPhase: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "已断开"
        case .connecting: return "连接中"
        case .connected: return "已连接"
        case .failed: return "失败"
        }
    }
}

enum MachineFilter: Hashable, Sendable {
    case all
    case untagged
    case tag(String)
}

struct LoadPoint: Equatable, Sendable {
    var at: Date
    var one: Double
    var five: Double
    var fifteen: Double
}

struct SFTPPreview: Identifiable, Equatable {
    var name: String
    var path: String
    var text: String
    var id: String { path }
}

enum SidebarItem: Hashable, Identifiable {
    case dashboard
    case machines
    case sshKeys
    case terminalHome
    case session(UUID)
    case sftpHome
    case sftp(UUID)

    var id: String {
        switch self {
        case .dashboard: return "dashboard"
        case .machines: return "machines"
        case .sshKeys: return "sshKeys"
        case .terminalHome: return "terminal-home"
        case .session(let id): return "session-\(id.uuidString)"
        case .sftpHome: return "sftp-home"
        case .sftp(let id): return "sftp-\(id.uuidString)"
        }
    }
}

@MainActor
@Observable
final class HostRuntime {
    let hostID: UUID
    var phase: ConnectionPhase = .idle
    var monitorPhase: ConnectionPhase = .idle
    var metrics: HostMetrics?
    var loadHistory: [LoadPoint] = []
    var latency = LatencyWindow()
    var lastError: String?
    let progress = ConnectionProgress()
    let terminal = TerminalSessionController()

    let engine = SSHEngine()
    let monitorEngine = SSHEngine()
    let sftpEngine = SSHEngine()
    var parser = LinuxMetricsParser()
    var metricsTask: Task<Void, Never>?
    var monitorTask: Task<Void, Never>?
    var shellTask: Task<Void, Never>?
    var sftpTask: Task<Void, Never>?
    var sftpPhase: ConnectionPhase = .idle
    var sftpClient: SFTPClient?
    var sftpPath = "/"
    var sftpListings: [SFTPListingItem] = []
    var sftpStatus = ""
    var sftpBusy = false

    init(hostID: UUID) {
        self.hostID = hostID
    }

    var isOnline: Bool {
        if case .connected = phase { return true }
        if case .connected = monitorPhase { return true }
        return false
    }

    var reachability: DashboardReachability {
        if isOnline {
            return latencySeconds == nil ? .connecting : .online
        }
        switch monitorPhase {
        case .connecting:
            return .connecting
        case .failed:
            return .offline
        case .idle, .connected:
            switch phase {
            case .connecting:
                return .connecting
            default:
                return .offline
            }
        }
    }

    func stop() {
        metricsTask?.cancel()
        monitorTask?.cancel()
        shellTask?.cancel()
        metricsTask = nil
        monitorTask = nil
        shellTask = nil
        terminal.unbind()
        progress.reset()
        let engine = self.engine
        let monitorEngine = self.monitorEngine
        Task {
            await engine.close()
            await monitorEngine.close()
        }
        phase = .idle
        monitorPhase = .idle
        metrics = nil
        loadHistory = []
        latency.reset()
    }

    func stopSFTP() {
        sftpTask?.cancel()
        sftpTask = nil
        sftpBusy = false
        sftpStatus = ""
        sftpListings = []
        sftpPath = "/"
        let client = sftpClient
        sftpClient = nil
        sftpPhase = .idle
        let engine = sftpEngine
        Task {
            try? await client?.close()
            await engine.close()
        }
    }

    func stopAll() {
        stop()
        stopSFTP()
    }

    var latencySeconds: Double? { latency.medianSeconds }

    func recordLoad(from metrics: HostMetrics) {
        guard let load = metrics.loadAverage else { return }
        loadHistory.append(LoadPoint(at: metrics.sampledAt, one: load.0, five: load.1, fifteen: load.2))
        if loadHistory.count > 150 {
            loadHistory.removeFirst(loadHistory.count - 150)
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var hosts: [HostRecord] = []
    var keys: [SSHKeyRecord] = []
    var sidebarSelection: SidebarItem? = .dashboard
    var machineSearch: String = ""
    var machineFilter: MachineFilter = .all
    var dashboardSearch: String = ""
    var dashboardFilter: MachineFilter = .all
    var editor: HostEditorState?
    var keyEditor: KeyEditorState?
    var importMessage: String?
    var importDraft: SSHImportDraft?
    var isBatchEditing = false
    var selectedHostIDs: Set<UUID> = []
    var settings = AppSettings()
    var sshDebugLogs: [ConnectionLogLine] = []
    var detachedSessionIDs: Set<UUID> = []
    var sessionInspectorPresented = false
    var sessionInspectorTab: TerminalInspectorTab = .status
    var sessionFontSheetPresented = false
    var configSyncNeedsRestart = false
    var configSyncError: String?
    private(set) var runtimes: [UUID: HostRuntime] = [:]

    private let store: HostStore
    private let keyStore: KeyStore
    private let secrets: SecretStore
    private let importer: SSHConfigImporter
    private let settingsStore: SettingsStore

    init(
        store: HostStore = HostStore(),
        keyStore: KeyStore = KeyStore(),
        secrets: SecretStore = SecretStore(),
        importer: SSHConfigImporter = SSHConfigImporter(),
        settingsStore: SettingsStore = SettingsStore()
    ) {
        self.store = store
        self.keyStore = keyStore
        self.secrets = secrets
        self.importer = importer
        self.settingsStore = settingsStore
        if let loaded = try? settingsStore.load() {
            settings = loaded
        }
        do {
            hosts = try store.load()
        } catch {
            importMessage = "Could not load saved hosts: \(error.localizedDescription)"
        }
        do {
            keys = try keyStore.load()
        } catch {
            importMessage = [importMessage, "Could not load saved keys: \(error.localizedDescription)"]
                .compactMap { $0 }
                .joined(separator: "\n")
        }
    }

    var selectedHost: HostRecord? {
        guard case .session(let id) = sidebarSelection else { return nil }
        return hosts.first { $0.id == id }
    }

    var filteredHosts: [HostRecord] {
        var result: [HostRecord]
        switch machineFilter {
        case .all:
            result = hosts
        case .untagged:
            result = hosts.filter(\.tags.isEmpty)
        case .tag(let tag):
            result = hosts.filter { host in
                host.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
        }
        let query = machineSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return result }
        return result.filter { host in
            host.displayName.localizedCaseInsensitiveContains(query)
                || host.hostname.localizedCaseInsensitiveContains(query)
                || host.username.localizedCaseInsensitiveContains(query)
                || (host.group?.localizedCaseInsensitiveContains(query) ?? false)
                || host.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var knownGroups: [String] {
        Array(Set(hosts.compactMap { HostRecord.normalizedGroup($0.group) })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    var knownTags: [String] {
        Array(Set(hosts.flatMap(\.tags).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var connectedCount: Int {
        hosts.filter { runtime(for: $0.id).phase == .connected }.count
    }

    var dashboardSortableHosts: [HostRecord] {
        DashboardHostOrder.sorted(hosts.filter(\.showOnDashboard), by: settings.dashboardHostIDs)
    }

    var dashboardHosts: [HostRecord] {
        var result = dashboardSortableHosts
        switch dashboardFilter {
        case .all:
            break
        case .untagged:
            result = result.filter(\.tags.isEmpty)
        case .tag(let tag):
            result = result.filter { host in
                host.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
        }
        let query = dashboardSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return result }
        return result.filter { host in
            host.displayName.localizedCaseInsensitiveContains(query)
                || host.hostname.localizedCaseInsensitiveContains(query)
                || host.username.localizedCaseInsensitiveContains(query)
                || (host.group?.localizedCaseInsensitiveContains(query) ?? false)
                || host.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var dashboardOnlineCount: Int {
        dashboardHosts.filter { runtime(for: $0.id).reachability == .online }.count
    }

    var dashboardOfflineCount: Int {
        dashboardHosts.filter { runtime(for: $0.id).reachability == .offline }.count
    }

    var activeSessions: [HostRecord] {
        hosts.filter {
            switch runtime(for: $0.id).phase {
            case .connecting, .connected: return true
            default: return false
            }
        }
    }

    var activeSFTPSessions: [HostRecord] {
        hosts.filter {
            switch runtime(for: $0.id).sftpPhase {
            case .connecting, .connected: return true
            default: return false
            }
        }
    }

    func runtime(for id: UUID) -> HostRuntime {
        if let existing = runtimes[id] {
            return existing
        }
        let created = HostRuntime(hostID: id)
        created.terminal.isBellEnabled = { [weak self] in
            self?.settings.terminalBellEnabled ?? true
        }
        runtimes[id] = created
        return created
    }

    func moveDashboardHosts(from source: IndexSet, to destination: Int) {
        var ordered = dashboardSortableHosts
        ordered.move(fromOffsets: source, toOffset: destination)
        settings.dashboardHostIDs = ordered.map(\.id)
        persistSettings()
    }

    func updateHost(_ id: UUID, _ body: (inout HostRecord) -> Void) {
        guard let index = hosts.firstIndex(where: { $0.id == id }) else { return }
        body(&hosts[index])
        try? store.save(hosts)
    }

    func setConfigSyncDestination(_ next: ConfigSyncDestination) {
        do {
            try ConfigSync.apply(next)
            configSyncNeedsRestart = true
            configSyncError = nil
        } catch {
            configSyncError = error.localizedDescription
        }
    }

    func persistSettings() {
        var next = settings
        next.clamp()
        settings = next
        try? settingsStore.save(next)
        applyAppearance()
    }

    func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    var isDarkAppearance: Bool {
        switch settings.appearance {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    func appendSSHLog(_ event: SSHClientLogEvent) {
        sshDebugLogs.append(ConnectionLogLine(event: event))
        if sshDebugLogs.count > 400 {
            sshDebugLogs.removeFirst(sshDebugLogs.count - 400)
        }
    }

    func clearSSHDebugLogs() {
        sshDebugLogs.removeAll()
    }

    func beginAddHost() {
        sidebarSelection = .machines
        editor = HostEditorState(record: HostRecord(name: "", hostname: "", username: NSUserName()))
    }

    func sshConfigMatch(for host: HostRecord) -> HostRecord? {
        (try? importer.lookup(alias: host.hostname)) ?? (try? importer.lookup(alias: host.name))
    }

    func applySSHConfigToEditor() {
        guard var state = editor else { return }
        let isNew = !hosts.contains { $0.id == state.record.id }
        guard isNew else { return }
        let alias = state.record.hostname.isEmpty ? state.record.name : state.record.hostname
        guard let match = (try? importer.lookup(alias: alias)) else { return }
        if let username = SSHConfigImporter.usernameToApply(
            current: state.record.username,
            fromConfig: match.username,
            macUsername: NSUserName(),
            lastAutoFilled: state.usernameFromSSHConfig
        ) {
            state.record.username = username
            state.usernameFromSSHConfig = username
        }
        if state.record.name.isEmpty {
            state.record.name = match.name
        }
        editor = state
    }

    func applySSHConfigUsernameToEditor() {
        guard var state = editor else { return }
        let alias = state.record.hostname.isEmpty ? state.record.name : state.record.hostname
        guard let match = (try? importer.lookup(alias: alias)) else { return }
        state.record.username = match.username
        state.usernameFromSSHConfig = match.username
        editor = state
    }

    func applySSHConfig(to host: HostRecord) {
        guard let match = sshConfigMatch(for: host) else { return }
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        var updated = hosts[index]
        updated.username = match.username
        updated.port = match.port
        if let path = match.privateKeyPath {
            updated.authKind = .privateKey
            updated.privateKeyPath = path
        }
        hosts[index] = updated
        try? store.save(hosts)
    }

    func applySSHConfigUsername(to host: HostRecord) {
        guard let match = sshConfigMatch(for: host) else { return }
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        hosts[index].username = match.username
        try? store.save(hosts)
    }

    func beginEditHost(_ host: HostRecord) {
        var state = HostEditorState(record: host)
        state.password = (try? secrets.get(account: secrets.passwordAccount(for: host.id))) ?? ""
        state.passphrase = (try? secrets.get(account: secrets.passphraseAccount(for: host.id))) ?? ""
        editor = state
    }

    func saveEditor() throws {
        guard var state = editor else { return }
        state.record.name = state.record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        state.record.hostname = state.record.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        state.record.username = state.record.username.trimmingCharacters(in: .whitespacesAndNewlines)
        state.record.group = HostRecord.normalizedGroup(state.record.group)
        state.record.tags = HostRecord.normalizedTags(state.record.tags)
        state.record.notes = state.record.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        state.record.defaultSFTPPath = HostRecord.normalizedSFTPPath(state.record.defaultSFTPPath)
        guard !state.record.hostname.isEmpty else { throw HostpaneSSHError.missingHostname }
        guard !state.record.username.isEmpty else { throw HostpaneSSHError.missingUsername }
        if state.record.name.isEmpty {
            state.record.name = state.record.hostname
        }
        if let index = hosts.firstIndex(where: { $0.id == state.record.id }) {
            hosts[index] = state.record
        } else {
            hosts.append(state.record)
        }
        try persistSecrets(state)
        try store.save(hosts)
        sidebarSelection = .machines
        editor = nil
    }

    func toggleHostSelection(_ id: UUID) {
        if selectedHostIDs.contains(id) {
            selectedHostIDs.remove(id)
        } else {
            selectedHostIDs.insert(id)
        }
    }

    func selectAllFilteredHosts() {
        selectedHostIDs = Set(filteredHosts.map(\.id))
    }

    func beginBatchEditing() {
        isBatchEditing = true
        selectedHostIDs = []
        sidebarSelection = .machines
    }

    func endBatchEditing() {
        isBatchEditing = false
        selectedHostIDs = []
    }

    func deleteSelectedHosts() throws {
        let doomed = hosts.filter { selectedHostIDs.contains($0.id) }
        for host in doomed {
            try deleteHost(host)
        }
        endBatchEditing()
    }

    func setGroupForSelected(_ group: String?) {
        let normalized = HostRecord.normalizedGroup(group)
        for index in hosts.indices where selectedHostIDs.contains(hosts[index].id) {
            hosts[index].group = normalized
        }
        try? store.save(hosts)
    }

    func addTagToSelected(_ tag: String) {
        let tags = HostRecord.normalizedTags([tag])
        guard let tag = tags.first else { return }
        for index in hosts.indices where selectedHostIDs.contains(hosts[index].id) {
            hosts[index].tags = HostRecord.normalizedTags(hosts[index].tags + [tag])
        }
        try? store.save(hosts)
    }

    func deleteHost(_ host: HostRecord) throws {
        disconnect(host)
        closeSFTP(host)
        hosts.removeAll { $0.id == host.id }
        runtimes[host.id] = nil
        if settings.dashboardHostIDs.contains(host.id) {
            settings.dashboardHostIDs.removeAll { $0 == host.id }
            persistSettings()
        }
        try? secrets.delete(account: secrets.passwordAccount(for: host.id))
        try? secrets.delete(account: secrets.passphraseAccount(for: host.id))
        try store.save(hosts)
        if case .session(let id) = sidebarSelection, id == host.id {
            sidebarSelection = .machines
        }
        if case .sftp(let id) = sidebarSelection, id == host.id {
            sidebarSelection = .machines
        }
    }

    func importSSHConfig() {
        beginImportSSHConfig()
    }

    func beginImportSSHConfig() {
        do {
            let parsed = try importer.importHosts()
            if parsed.isEmpty {
                importMessage = "没有从 ~/.ssh/config 读到可用的 Host。"
                return
            }
            importDraft = SSHImportDraft(
                candidates: parsed.map { host in
                    let exists = hosts.contains {
                        $0.hostname == host.hostname && $0.username == host.username && $0.port == host.port
                    }
                    return SSHImportRow(host: host, alreadyImported: exists, selected: !exists)
                }
            )
        } catch {
            importMessage = "读取 ~/.ssh/config 失败：\(error.localizedDescription)"
        }
    }

    func toggleImportRow(_ id: UUID) {
        guard var draft = importDraft,
              let index = draft.candidates.firstIndex(where: { $0.id == id }),
              !draft.candidates[index].alreadyImported
        else { return }
        draft.candidates[index].selected.toggle()
        importDraft = draft
    }

    func setImportSelection(allNew: Bool) {
        guard var draft = importDraft else { return }
        for index in draft.candidates.indices where !draft.candidates[index].alreadyImported {
            draft.candidates[index].selected = allNew
        }
        importDraft = draft
    }

    func confirmImportSSHConfig() {
        guard let draft = importDraft else { return }
        var addedIDs: [UUID] = []
        for row in draft.candidates where row.selected && !row.alreadyImported {
            hosts.append(row.host)
            addedIDs.append(row.host.id)
        }
        try? store.save(hosts)
        importDraft = nil
        sidebarSelection = .machines
        if addedIDs.isEmpty {
            importMessage = "没有勾选新的机器。"
            return
        }
        isBatchEditing = true
        selectedHostIDs = Set(addedIDs)
        importMessage = "已加入 \(addedIDs.count) 台机器。可以勾选后批量改组、加标签或删除。"
    }

    func openHost(_ host: HostRecord) {
        sidebarSelection = .machines
    }

    func probeSSH() async throws {
        guard let state = editor else { return }
        var host = state.record
        host.hostname = host.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        host.username = host.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.hostname.isEmpty else { throw HostpaneSSHError.missingHostname }
        guard !host.username.isEmpty else { throw HostpaneSSHError.missingUsername }
        let engine = SSHEngine()
        do {
            try await engine.connect(
                host: host,
                secrets: secrets,
                overrides: SSHSecretOverrides(
                    password: state.password,
                    passphrase: state.passphrase
                ),
                settings: settings
            )
            await engine.close()
        } catch {
            await engine.close()
            throw error
        }
    }

    func openTerminal(_ host: HostRecord) {
        detachedSessionIDs.remove(host.id)
        sidebarSelection = .session(host.id)
        let runtime = runtime(for: host.id)
        switch runtime.phase {
        case .connecting, .connected:
            return
        case .idle, .failed:
            startConnection(host, sampleMetrics: true)
        }
    }

    func restartTerminal(_ host: HostRecord) {
        startConnection(host, sampleMetrics: true)
    }

    func openSessionInNewWindow(_ host: HostRecord) {
        detachedSessionIDs.insert(host.id)
        if case .session(let id) = sidebarSelection, id == host.id {
            sidebarSelection = .dashboard
        }
        openTerminalIfNeeded(host)
    }

    func sessionWindowClosed(_ id: UUID) {
        detachedSessionIDs.remove(id)
    }

    private func openTerminalIfNeeded(_ host: HostRecord) {
        let runtime = runtime(for: host.id)
        switch runtime.phase {
        case .connecting, .connected:
            return
        case .idle, .failed:
            startConnection(host, sampleMetrics: true)
        }
    }

    func openSFTP(_ host: HostRecord) {
        sidebarSelection = .sftp(host.id)
        let runtime = runtime(for: host.id)
        switch runtime.sftpPhase {
        case .connecting:
            return
        case .connected:
            if runtime.sftpListings.isEmpty {
                Task { await refreshSFTP(host) }
            }
        case .idle, .failed:
            startSFTP(host)
        }
    }

    func closeSFTP(_ host: HostRecord) {
        runtime(for: host.id).stopSFTP()
        if case .sftp(let id) = sidebarSelection, id == host.id {
            sidebarSelection = .machines
        }
    }

    func restartSFTP(_ host: HostRecord) {
        let path = runtime(for: host.id).sftpPath
        startSFTP(host, initialPath: path)
    }

    func startSFTP(_ host: HostRecord, initialPath: String? = nil) {
        guard !host.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let runtime = runtime(for: host.id)
        runtime.sftpTask?.cancel()
        let previousClient = runtime.sftpClient
        runtime.sftpClient = nil
        runtime.sftpListings = []
        runtime.sftpBusy = false
        runtime.sftpStatus = "正在连接…"
        runtime.sftpPhase = .connecting
        runtime.sftpPath = HostRecord.normalizedSFTPPath(initialPath ?? host.defaultSFTPPath)
        runtime.lastError = nil
        let engine = runtime.sftpEngine
        let secrets = self.secrets
        let settings = self.settings
        runtime.sftpTask = Task { [weak self, weak runtime] in
            guard let self, let runtime else { return }
            try? await previousClient?.close()
            do {
                try await engine.connect(
                    host: host,
                    secrets: secrets,
                    settings: settings,
                    keepAlive: .sftp
                ) { event in
                    Task { @MainActor [weak self] in
                        self?.appendSSHLog(event)
                    }
                }
                guard !Task.isCancelled else { return }
                let client = try await engine.openSFTP()
                guard !Task.isCancelled else {
                    try? await client.close()
                    return
                }
                runtime.sftpClient = client
                runtime.sftpPhase = .connected
                try await self.loadSFTPListing(runtime, path: runtime.sftpPath)
            } catch is CancellationError {
                runtime.sftpPhase = .idle
            } catch {
                runtime.sftpPhase = .failed(describeSSHError(error))
                runtime.lastError = describeSSHError(error)
            }
        }
    }

    func refreshSFTP(_ host: HostRecord) async {
        let runtime = runtime(for: host.id)
        guard runtime.sftpClient != nil else {
            startSFTP(host)
            return
        }
        do {
            try await loadSFTPListing(runtime, path: runtime.sftpPath)
        } catch {
            runtime.sftpStatus = describeSSHError(error)
        }
    }

    func sftpOpen(_ host: HostRecord, item: SFTPListingItem) async {
        switch item.kind {
        case .directory:
            await sftpChangeDirectory(host, path: item.path)
        case .file, .symbolicLink, .other:
            await sftpDownload(host, items: [item])
        }
    }

    func sftpChangeDirectory(_ host: HostRecord, path: String) async {
        let runtime = runtime(for: host.id)
        do {
            try await loadSFTPListing(runtime, path: path)
        } catch {
            runtime.sftpStatus = describeSSHError(error)
        }
    }

    func sftpGoUp(_ host: HostRecord) async {
        let runtime = runtime(for: host.id)
        await sftpChangeDirectory(host, path: SFTPPaths.parent(runtime.sftpPath))
    }

    func sftpMakeDirectory(_ host: HostRecord, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let runtime = runtime(for: host.id)
        guard let client = runtime.sftpClient else { return }
        runtime.sftpBusy = true
        defer { runtime.sftpBusy = false }
        do {
            try await client.makeDirectory(SFTPPaths.join(runtime.sftpPath, trimmed))
            try await loadSFTPListing(runtime, path: runtime.sftpPath)
        } catch {
            runtime.sftpStatus = describeSSHError(error)
        }
    }

    func sftpRename(_ host: HostRecord, item: SFTPListingItem, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let runtime = runtime(for: host.id)
        guard let client = runtime.sftpClient else { return }
        runtime.sftpBusy = true
        defer { runtime.sftpBusy = false }
        do {
            try await client.rename(item.path, to: SFTPPaths.join(runtime.sftpPath, trimmed))
            try await loadSFTPListing(runtime, path: runtime.sftpPath)
        } catch {
            runtime.sftpStatus = describeSSHError(error)
        }
    }

    func sftpDelete(_ host: HostRecord, items: [SFTPListingItem]) async {
        let runtime = runtime(for: host.id)
        guard let client = runtime.sftpClient else { return }
        runtime.sftpBusy = true
        defer { runtime.sftpBusy = false }
        do {
            for item in items where item.name != "." && item.name != ".." {
                try await deleteSFTPItem(client, item: item)
            }
            try await loadSFTPListing(runtime, path: runtime.sftpPath)
        } catch {
            runtime.sftpStatus = describeSSHError(error)
        }
    }

    func sftpUpload(_ host: HostRecord, files: [URL]) async {
        let runtime = runtime(for: host.id)
        guard let client = runtime.sftpClient else { return }
        runtime.sftpBusy = true
        defer { runtime.sftpBusy = false }
        do {
            for file in files {
                let accessed = file.startAccessingSecurityScopedResource()
                defer { if accessed { file.stopAccessingSecurityScopedResource() } }
                let name = file.lastPathComponent
                let remote = SFTPPaths.join(runtime.sftpPath, name)
                runtime.sftpStatus = "正在上传 \(name)…"
                let isDirectory = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory == true {
                    _ = try await client.uploadDirectory(from: file, to: remote)
                } else {
                    _ = try await client.uploadFile(from: file, to: remote)
                }
            }
            try await loadSFTPListing(runtime, path: runtime.sftpPath)
            runtime.sftpStatus = "上传完成"
        } catch {
            runtime.sftpStatus = describeSSHError(error)
        }
    }

    func sftpDownload(_ host: HostRecord, items: [SFTPListingItem], to directory: URL? = nil) async {
        let runtime = runtime(for: host.id)
        guard let client = runtime.sftpClient else { return }
        let destination = directory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let destination else { return }
        runtime.sftpBusy = true
        defer { runtime.sftpBusy = false }
        do {
            for item in items {
                let local = destination.appendingPathComponent(item.name)
                runtime.sftpStatus = "正在下载 \(item.name)…"
                if item.kind == .directory {
                    _ = try await client.downloadDirectory(item.path, to: local)
                } else {
                    _ = try await client.downloadFile(item.path, to: local, expectedSize: item.size)
                }
            }
            runtime.sftpStatus = "已保存到 \(destination.path)"
        } catch {
            runtime.sftpStatus = describeSSHError(error)
        }
    }

    func sftpPreview(_ host: HostRecord, item: SFTPListingItem) async -> SFTPPreview? {
        let runtime = runtime(for: host.id)
        guard let client = runtime.sftpClient, item.kind == .file else { return nil }
        let limit: UInt64 = 512 * 1024
        if let size = item.size, size > limit { return nil }
        runtime.sftpBusy = true
        defer { runtime.sftpBusy = false }
        do {
            let data = try await client.readFile(item.path)
            if settings.textFileOpener == .defaultApp {
                let cache = SettingsStore.previewCacheDirectory()
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                let file = cache.appendingPathComponent(item.name)
                try Data(data).write(to: file)
                NSWorkspace.shared.open(file)
                return nil
            }
            let bytes = Data(data)
            if let text = String(data: bytes, encoding: .utf8) {
                return SFTPPreview(name: item.name, path: item.path, text: text)
            }
            return nil
        } catch {
            runtime.sftpStatus = describeSSHError(error)
            return nil
        }
    }

    private func loadSFTPListing(_ runtime: HostRuntime, path: String) async throws {
        guard let client = runtime.sftpClient else { throw HostpaneSSHError.notConnected }
        runtime.sftpBusy = true
        defer { runtime.sftpBusy = false }
        let requested = SFTPPaths.normalize(path)
        let resolved: String
        if let real = try? await client.realPath(requested), !real.filename.isEmpty {
            resolved = SFTPPaths.normalize(real.filename)
        } else {
            resolved = requested
        }
        let entries = try await client.listDirectory(resolved)
        runtime.sftpPath = resolved
        let includeHidden = settings.sftpShowHiddenFiles
        runtime.sftpListings = entries.compactMap {
            SFTPPaths.item(from: $0, directory: resolved, includeHidden: includeHidden)
        }
        .sorted { lhs, rhs in
            let leftRank = hiddenSortRank(lhs.name, kind: lhs.kind)
            let rightRank = hiddenSortRank(rhs.name, kind: rhs.kind)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        runtime.sftpStatus = "\(runtime.sftpListings.count) 项"
        runtime.sftpPhase = .connected
    }

    private func hiddenSortRank(_ name: String, kind: SFTPEntryKind) -> Int {
        if name == "." { return 0 }
        if name == ".." { return 1 }
        if kind == .directory { return 2 }
        return 3
    }

    private func deleteSFTPItem(_ client: SFTPClient, item: SFTPListingItem) async throws {
        if item.kind == .directory {
            let children = try await client.listDirectory(item.path)
            for child in children {
                guard child.filename != ".", child.filename != ".." else { continue }
                guard let listing = SFTPPaths.item(
                    from: child,
                    directory: item.path,
                    includeHidden: true
                ) else { continue }
                try await deleteSFTPItem(client, item: listing)
            }
            try await client.removeDirectory(item.path)
        } else {
            try await client.removeFile(item.path)
        }
    }

    func startDashboardMonitors() {
        for host in hosts {
            if host.showOnDashboard {
                startMonitor(host)
            } else {
                stopMonitor(host)
            }
        }
    }

    func refreshDashboard() {
        for host in hosts where host.showOnDashboard {
            startMonitor(host, restart: true)
        }
    }

    func refreshFailedDashboard() {
        for host in hosts where host.showOnDashboard {
            if runtime(for: host.id).reachability == .offline {
                startMonitor(host, restart: true)
            }
        }
    }

    func stopMonitor(_ host: HostRecord) {
        let runtime = runtime(for: host.id)
        switch runtime.phase {
        case .connecting, .connected:
            return
        case .idle, .failed:
            break
        }
        runtime.monitorTask?.cancel()
        runtime.monitorTask = nil
        runtime.monitorPhase = .idle
        let engine = runtime.monitorEngine
        Task { await engine.close() }
    }

    func startMonitor(_ host: HostRecord, restart: Bool = false) {
        guard !host.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let runtime = runtime(for: host.id)
        switch runtime.phase {
        case .connecting, .connected:
            return
        case .idle, .failed:
            break
        }
        if !restart {
            switch runtime.monitorPhase {
            case .connecting, .connected:
                return
            case .idle, .failed:
                break
            }
        }
        runtime.monitorTask?.cancel()
        runtime.monitorTask = nil
        runtime.monitorPhase = .connecting
        runtime.lastError = nil
        runtime.parser = LinuxMetricsParser()
        runtime.loadHistory = []
        runtime.latency.reset()
        let engine = runtime.monitorEngine
        let secrets = self.secrets
        let settings = self.settings
        runtime.monitorTask = Task { [weak self, weak runtime] in
            guard let self, let runtime else { return }
            await Task.yield()
            let started = ContinuousClock.now
            await engine.close()
            do {
                try await engine.connect(host: host, secrets: secrets, settings: settings) { event in
                    Task { @MainActor [weak self] in
                        self?.appendSSHLog(event)
                    }
                }
                await Self.holdConnectingBadge(from: started)
                guard !Task.isCancelled else { return }
                runtime.monitorPhase = .connected
                await self.sampleLoop(runtime: runtime, engine: engine)
                guard !Task.isCancelled else { return }
                runtime.monitorPhase = .idle
            } catch is CancellationError {
                return
            } catch {
                await Self.holdConnectingBadge(from: started)
                guard !Task.isCancelled else { return }
                runtime.monitorPhase = .failed(describeSSHError(error))
                runtime.lastError = describeSSHError(error)
            }
        }
    }

    func connect(_ host: HostRecord) {
        startConnection(host, sampleMetrics: true)
    }

    func dismissConnectionCard(_ host: HostRecord) {
        let runtime = runtime(for: host.id)
        switch runtime.phase {
        case .connected:
            runtime.progress.cardVisible = false
        default:
            disconnect(host)
        }
    }

    func sessionDidEnd(_ host: HostRecord) {
        runtime(for: host.id).stop()
        sidebarSelection = .machines
        resumeMonitorIfNeeded(host)
    }

    func disconnect(_ host: HostRecord) {
        runtime(for: host.id).stop()
        if case .session(let id) = sidebarSelection, id == host.id {
            sidebarSelection = .machines
        }
        resumeMonitorIfNeeded(host)
    }

    private func resumeMonitorIfNeeded(_ host: HostRecord) {
        guard let current = hosts.first(where: { $0.id == host.id }), current.showOnDashboard else { return }
        startMonitor(current)
    }

    private func startConnection(_ host: HostRecord, sampleMetrics: Bool) {
        let runtime = runtime(for: host.id)
        runtime.stop()
        runtime.phase = .connecting
        runtime.lastError = nil
        runtime.parser = LinuxMetricsParser()
        runtime.loadHistory = []
        runtime.latency.reset()
        runtime.progress.reset()
        runtime.progress.appendSetup(host: host)
        let engine = runtime.engine
        let secrets = self.secrets
        let settings = self.settings
        runtime.metricsTask = Task { [weak self, weak runtime] in
            guard let self, let runtime else { return }
            do {
                let hostID = host.id
                try await engine.connect(host: host, secrets: secrets, settings: settings) { event in
                    Task { @MainActor [weak self] in
                        self?.runtime(for: hostID).progress.ingest(event)
                        self?.appendSSHLog(event)
                    }
                }
                runtime.progress.mark(.network, .done)
                runtime.progress.mark(.handshake, .done)
                runtime.progress.mark(.authentication, .done)
                runtime.progress.mark(.shell, .running)
                runtime.phase = .connected
                runtime.terminal.onSessionEnded = { [weak self] in
                    self?.sessionDidEnd(host)
                }
                runtime.terminal.onReadyToOpenShell = { [weak self] columns, rows in
                    Task { @MainActor in
                        await self?.startShell(
                            host: host,
                            runtime: runtime,
                            columns: columns,
                            rows: rows
                        )
                    }
                }
                try await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, runtime.phase == .connected else { return }
                runtime.progress.cardVisible = false
                try await Task.sleep(for: .milliseconds(400))
                if runtime.shellTask == nil {
                    await self.startShell(host: host, runtime: runtime, columns: 120, rows: 36)
                }
                if sampleMetrics {
                    await self.sampleLoop(runtime: runtime, engine: engine)
                }
            } catch is CancellationError {
                runtime.phase = .idle
            } catch {
                runtime.progress.failRemaining()
                runtime.phase = .failed(describeSSHError(error))
                runtime.lastError = describeSSHError(error)
            }
        }
    }

    private func persistSecrets(_ state: HostEditorState) throws {
        let host = state.record
        if host.authKind == .password {
            if state.password.isEmpty {
                try secrets.delete(account: secrets.passwordAccount(for: host.id))
            } else {
                try secrets.set(state.password, account: secrets.passwordAccount(for: host.id))
            }
        }
        if host.authKind == .privateKey {
            if state.passphrase.isEmpty {
                try secrets.delete(account: secrets.passphraseAccount(for: host.id))
            } else {
                try secrets.set(state.passphrase, account: secrets.passphraseAccount(for: host.id))
            }
        }
    }

    private func startShell(
        host: HostRecord,
        runtime: HostRuntime,
        columns: UInt32,
        rows: UInt32
    ) async {
        guard runtime.shellTask == nil, runtime.phase == .connected else { return }
        do {
            let session = try await runtime.engine.openShell(columns: columns, rows: rows)
            runtime.terminal.bind(session: session, columns: columns, rows: rows)
            runtime.progress.mark(.shell, .done)
            runtime.shellTask = Task {
                await runtime.terminal.runEventLoop()
            }
            runtime.terminal.requestFocus()
        } catch {
            runtime.lastError = "Terminal: \(describeSSHError(error))"
        }
    }

    private static func holdConnectingBadge(from start: ContinuousClock.Instant) async {
        let elapsed = durationToSeconds(ContinuousClock.now - start)
        let minimum = 0.45
        if elapsed < minimum {
            try? await Task.sleep(for: .milliseconds(Int((minimum - elapsed) * 1_000)))
        }
    }

    private func sampleLoop(runtime: HostRuntime, engine: SSHEngine) async {
        var isFirst = true
        while !Task.isCancelled {
            do {
                let pingStarted = ContinuousClock.now
                _ = try await engine.execute(LinuxMetricsProbe.latencyCommand)
                runtime.latency.push(durationToSeconds(ContinuousClock.now - pingStarted))

                let result = try await engine.execute(LinuxMetricsProbe.remoteCommand)
                var metrics = try runtime.parser.consume(String(decoding: result.standardOutput, as: UTF8.self))
                metrics.sshLatencySeconds = runtime.latencySeconds
                runtime.metrics = metrics
                runtime.recordLoad(from: metrics)
                if !metrics.isLinux {
                    runtime.lastError = HostpaneSSHError.unsupportedOS(metrics.operatingSystem).errorDescription
                }
            } catch is CancellationError {
                return
            } catch {
                runtime.lastError = describeSSHError(error)
            }
            let delay: Duration = isFirst ? .milliseconds(400) : .seconds(2)
            isFirst = false
            try? await Task.sleep(for: delay)
        }
    }

    func beginAddExistingKey() {
        sidebarSelection = .sshKeys
        keyEditor = KeyEditorState(mode: .addExisting)
    }

    func beginGenerateKey() {
        sidebarSelection = .sshKeys
        keyEditor = KeyEditorState(mode: .generate)
    }

    func beginImportClipboard(text: String) {
        sidebarSelection = .sshKeys
        keyEditor = KeyEditorState(mode: .clipboard, publicKeyText: text)
    }

    func saveKeyEditor() throws {
        guard let state = keyEditor else { return }
        var imported: [SSHKeyRecord] = []
        switch state.mode {
        case .addExisting:
            let path = state.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { throw SSHKeyError.unreadableFile("(empty path)") }
            imported = try importRecords(fromFilePath: path, passphrase: state.passphrase)
            let named = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if imported.count == 1, !named.isEmpty {
                imported[0].name = named
            }
        case .generate:
            imported = [
                try SSHKeyFile.generateEd25519(
                    name: state.name,
                    comment: state.comment.isEmpty ? "hostpane" : state.comment,
                    passphrase: state.passphrase
                )
            ]
        case .clipboard:
            imported = SSHKeyFile.records(fromPublicKeyText: state.publicKeyText, origin: .clipboard)
            if imported.isEmpty { throw SSHKeyError.invalidPublicKey }
            let named = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if imported.count == 1, !named.isEmpty {
                imported[0].name = named
            }
        }
        var added = 0
        for record in imported {
            if let index = keys.firstIndex(where: { $0.fingerprint == record.fingerprint }) {
                if keys[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    keys[index].name = record.name
                }
                continue
            }
            if !record.privateKeyPath.isEmpty,
               keys.contains(where: { $0.privateKeyPath == record.privateKeyPath }) {
                continue
            }
            keys.append(record)
            added += 1
            if !state.passphrase.isEmpty {
                try secrets.set(state.passphrase, account: secrets.keyPassphraseAccount(for: record.id))
            }
        }
        if added > 0 {
            try keyStore.save(keys)
        }
        keyEditor = nil
    }

    func importKey(fromFilePath path: String) throws {
        let imported = try importRecords(fromFilePath: path, passphrase: "")
        _ = try mergeKeys(imported)
    }

    func importRecords(fromFilePath path: String, passphrase: String) throws -> [SSHKeyRecord] {
        if path.hasSuffix(".pub") || (try? String(contentsOfFile: path, encoding: .utf8)).map(SSHKeyFile.looksLikePublicKey) == true {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            let records = SSHKeyFile.records(fromPublicKeyText: text, origin: .file)
            if records.isEmpty { throw SSHKeyError.invalidPublicKey }
            return records
        }
        return [try SSHKeyFile.inspect(privateKeyPath: path)]
    }

    func mergeKeys(_ incoming: [SSHKeyRecord]) throws -> Int {
        var added = 0
        for record in incoming {
            if keys.contains(where: { $0.fingerprint == record.fingerprint }) { continue }
            if !record.privateKeyPath.isEmpty,
               keys.contains(where: { $0.privateKeyPath == record.privateKeyPath }) {
                continue
            }
            keys.append(record)
            added += 1
        }
        if added > 0 {
            try keyStore.save(keys)
        }
        return added
    }

    func refreshAgentKeys() async {
        for path in SSHAgentSockets.available() {
            do {
                let client = try SSHAgentClient(socketPath: path)
                let identities = try await client.identities()
                guard !identities.isEmpty else { continue }
                let records = identities.map(SSHAgentSockets.record(from:))
                _ = try? mergeKeys(records)
                return
            } catch {
                continue
            }
        }
    }

    func importKeysFromSSHDirectory() {
        do {
            let scanned = try SSHKeyFile.scanDefaultDirectory()
            var added = 0
            for key in scanned {
                if keys.contains(where: { $0.privateKeyPath == key.privateKeyPath }) { continue }
                keys.append(key)
                added += 1
            }
            try keyStore.save(keys)
            sidebarSelection = .sshKeys
            importMessage = added == 0
                ? "No new keys found in ~/.ssh."
                : "Imported \(added) key\(added == 1 ? "" : "s") from ~/.ssh."
        } catch {
            importMessage = "Key import failed: \(error.localizedDescription)"
        }
    }

    func deleteKey(_ key: SSHKeyRecord) throws {
        keys.removeAll { $0.id == key.id }
        try? secrets.delete(account: secrets.keyPassphraseAccount(for: key.id))
        try keyStore.save(keys)
    }
}

struct SSHImportRow: Identifiable, Hashable {
    var host: HostRecord
    var alreadyImported: Bool
    var selected: Bool

    var id: UUID { host.id }
}

struct SSHImportDraft: Identifiable {
    let id = UUID()
    var candidates: [SSHImportRow]

    var selectedNewCount: Int {
        candidates.filter { $0.selected && !$0.alreadyImported }.count
    }
}

struct HostEditorState: Identifiable {
    var record: HostRecord
    var password: String = ""
    var passphrase: String = ""
    var usernameFromSSHConfig: String?

    var id: UUID { record.id }
}

struct KeyEditorState: Identifiable {
    enum Mode {
        case addExisting
        case generate
        case clipboard
    }

    var mode: Mode
    var name: String = ""
    var path: String = ""
    var comment: String = ""
    var passphrase: String = ""
    var publicKeyText: String = ""

    var id: String {
        switch mode {
        case .generate: return "generate"
        case .addExisting: return "add-existing"
        case .clipboard: return "clipboard"
        }
    }
}
