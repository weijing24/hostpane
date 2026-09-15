import SwiftUI
import HostpaneCore

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var inspectedHostID: UUID?
    @State private var showingDashboardSort = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterRow
                    summaryRow
                    hostGrid
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(HostpaneTheme.page)
            .navigationTitle("仪表板")
            .toolbar {
                ToolbarItem {
                    Button {
                        showingDashboardSort = true
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .help("仪表板排序")
                    .disabled(model.hosts.filter(\.showOnDashboard).isEmpty)
                }
                ToolbarItem {
                    Menu {
                        Button("全部刷新", systemImage: "arrow.clockwise") {
                            model.refreshDashboard()
                        }
                        Button("仅刷新失败项", systemImage: "arrow.clockwise") {
                            model.refreshFailedDashboard()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新")
                    .menuIndicator(.visible)
                }
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.fixed)
                    DefaultToolbarItem(kind: .search)
                }
            }
            .searchable(text: $model.dashboardSearch, placement: .toolbar, prompt: "搜索")
            .navigationDestination(item: $inspectedHostID) { id in
                if let host = model.hosts.first(where: { $0.id == id }) {
                    HostInspectView(host: host)
                }
            }
            .sheet(isPresented: $showingDashboardSort) {
                DashboardSortSheet()
            }
        }
        .onAppear { model.startDashboardMonitors() }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("全部", selected: model.dashboardFilter == .all) {
                    model.dashboardFilter = .all
                }
                filterChip("无标签", selected: model.dashboardFilter == .untagged) {
                    model.dashboardFilter = .untagged
                }
                ForEach(model.knownTags, id: \.self) { tag in
                    filterChip(tag, selected: model.dashboardFilter == .tag(tag)) {
                        model.dashboardFilter = .tag(tag)
                    }
                }
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 16) {
            SummaryStatCard(
                title: "总计",
                value: model.dashboardHosts.count,
                dot: HostpaneTheme.total
            )
            SummaryStatCard(
                title: "在线",
                value: model.dashboardOnlineCount,
                dot: HostpaneTheme.online
            )
            SummaryStatCard(
                title: "离线",
                value: model.dashboardOfflineCount,
                dot: HostpaneTheme.offline
            )
        }
    }

    @ViewBuilder
    private var hostGrid: some View {
        if model.hosts.isEmpty {
            ContentUnavailableView {
                Label("还没有机器", systemImage: "server.rack")
            } description: {
                Text("添加一台机器，或从 ~/.ssh/config 导入 Host。")
            } actions: {
                Button("添加机器") { model.beginAddHost() }
                Button("导入 SSH Config") { model.beginImportSSHConfig() }
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else if model.hosts.filter(\.showOnDashboard).isEmpty {
            ContentUnavailableView {
                Label("仪表板是空的", systemImage: "gauge.with.needle")
            } description: {
                Text("在编辑机器里打开「在仪表板中显示状态」。")
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else if model.dashboardHosts.isEmpty {
            ContentUnavailableView {
                Label("没有匹配的机器", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("试试其他标签，或清空搜索。")
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(model.dashboardHosts) { host in
                    DashboardHostCard(host: host, runtime: model.runtime(for: host.id)) {
                        inspectedHostID = host.id
                    }
                }
            }
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().stroke(selected ? HostpaneTheme.accent.opacity(0.7) : Color.secondary.opacity(0.25))
                )
                .foregroundStyle(selected ? HostpaneTheme.accent : .secondary)
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardSortSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("仪表板排序")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 8)
            if model.dashboardSortableHosts.isEmpty {
                ContentUnavailableView {
                    Label("仪表板是空的", systemImage: "arrow.up.arrow.down")
                } description: {
                    Text("在编辑机器里打开「在仪表板中显示状态」。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.dashboardSortableHosts) { host in
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(host.displayName)
                                Text("\(host.username)@\(host.hostname):\(host.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove(perform: model.moveDashboardHosts)
                }
                .listStyle(.inset)
            }
            Text("拖动重新排序，顺序将自动保存。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 480, minHeight: 420)
    }
}

private struct SummaryStatCard: View {
    var title: String
    var value: Int
    var dot: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Circle()
                    .fill(dot)
                    .frame(width: 10, height: 10)
                Text("\(value)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }
}

private struct DashboardHostCard: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    let runtime: HostRuntime
    var onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            metaRow
            Divider().opacity(0.35)
            metricsRow
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(hovering ? HostpaneTheme.accent.opacity(0.7) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("查看详情") { onOpen() }
            Button("打开终端") { model.openTerminal(host) }
            Button("打开 SFTP") { model.openSFTP(host) }
            Button("打开 Docker") { model.openDocker(host) }
            Button("编辑") { model.beginEditHost(host) }
            Divider()
            Button("重新检测") { model.startMonitor(host, restart: true) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "server.rack")
                .font(.body)
                .foregroundStyle(HostpaneTheme.accent)
            Text(host.displayName)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
            if hovering {
                HStack(spacing: 8) {
                    CircleActionButton.terminal { model.openTerminal(host) }
                    CircleActionButton.sftp { model.openSFTP(host) }
                }
            }
            statusBadge
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(statusColor)
        }
        .help(statusHelp)
        .frame(minWidth: 64, alignment: .trailing)
    }

    private var metaRow: some View {
        HStack(spacing: 12) {
            meta(icon: "cpu", text: coresText)
            meta(icon: "memorychip", text: memoryText)
            meta(icon: "internaldrive", text: diskText)
            meta(icon: "clock", text: uptimeText)
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var metricsRow: some View {
        HStack(alignment: .center, spacing: 8) {
            RingMeter(
                title: "CPU",
                ratio: runtime.metrics?.cpuUsage,
                color: HostpaneTheme.usageColor(runtime.metrics?.cpuUsage),
                size: 52,
                titleOnTop: true
            )
            RingMeter(
                title: "RAM",
                ratio: runtime.metrics?.memoryUsedRatio,
                color: HostpaneTheme.usageColor(runtime.metrics?.memoryUsedRatio),
                size: 52,
                titleOnTop: true
            )
            RingMeter(
                title: "DISK",
                ratio: diskUsedRatio,
                color: HostpaneTheme.usageColor(diskUsedRatio),
                size: 52,
                titleOnTop: true
            )
            rateBlock(
                title: "网络",
                up: runtime.metrics?.netTransmitBytesPerSecond,
                down: runtime.metrics?.netReceiveBytesPerSecond,
                upLabel: "↑",
                downLabel: "↓"
            )
            rateBlock(
                title: "磁盘",
                up: runtime.metrics?.diskReadBytesPerSecond,
                down: runtime.metrics?.diskWriteBytesPerSecond,
                upLabel: "读",
                downLabel: "写"
            )
        }
    }

    private var statusColor: Color {
        switch runtime.reachability {
        case .online:
            if let latency = runtime.latencySeconds {
                return HostpaneTheme.latencyColor(latency)
            }
            return HostpaneTheme.loadLow
        case .connecting: return HostpaneTheme.connecting
        case .offline: return HostpaneTheme.offline
        }
    }

    private var statusText: String {
        switch runtime.reachability {
        case .online:
            if let latency = runtime.latencySeconds {
                return formatLatency(latency)
            }
            return "在线"
        case .connecting:
            return "连接中"
        case .offline:
            return "离线"
        }
    }

    private var statusHelp: String {
        if runtime.reachability == .offline, let error = runtime.lastError, !error.isEmpty {
            return error
        }
        if runtime.reachability == .online {
            return "SSH 往返时延（轻量探测，不是 ICMP）"
        }
        return "正在建立 SSH 监测连接"
    }

    private var coresText: String {
        let cores = runtime.metrics?.cpuCores ?? 0
        return cores > 0 ? "\(cores) 核" : "— 核"
    }

    private var memoryText: String {
        guard let metrics = runtime.metrics, metrics.memoryTotalBytes > 0 else { return "—" }
        return formatBytes(metrics.memoryTotalBytes)
    }

    private var diskText: String {
        guard let total = runtime.metrics?.localStorageBytes, total > 0 else { return "—" }
        return formatBytes(total)
    }

    private var diskUsedRatio: Double? {
        if let disk = runtime.metrics?.preferredDisk(mount: host.defaultMount), disk.totalBytes > 0 {
            return disk.usedRatio
        }
        guard let metrics = runtime.metrics, metrics.localStorageBytes > 0 else { return nil }
        return Double(metrics.localStorageUsedBytes) / Double(metrics.localStorageBytes)
    }

    private var uptimeText: String {
        guard let metrics = runtime.metrics else { return "—" }
        return formatUptime(metrics.uptimeSeconds)
    }

    private func meta(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
                .monospacedDigit()
        }
    }

    private func rateBlock(
        title: String,
        up: Double?,
        down: Double?,
        upLabel: String,
        downLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            rateLine(upLabel, up)
            rateLine(downLabel, down)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rateLine(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .leading)
            Text(value.map(formatCompactRate) ?? "—")
                .font(.subheadline.monospacedDigit().weight(.semibold))
        }
    }
}
