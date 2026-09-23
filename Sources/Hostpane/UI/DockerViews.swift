import SwiftUI
import HostpaneCore

struct DockerRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            DockerHomeView()
                .navigationDestination(item: $model.dockerInspectHostID) { id in
                    if let host = model.hosts.first(where: { $0.id == id }) {
                        DockerHostView(host: host)
                    } else {
                        ContentUnavailableView("找不到这台机器", systemImage: "questionmark.circle")
                    }
                }
        }
        .onAppear {
            for host in model.hosts {
                model.startMonitor(host)
            }
        }
    }
}

struct DockerHomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.hosts.isEmpty {
                    ContentUnavailableView {
                        Label("还没有机器", systemImage: "shippingbox")
                    } description: {
                        Text("添加一台机器后，可以在这里打开 Docker 面板。")
                    } actions: {
                        Button("添加机器") { model.beginAddHost() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else if model.dockerHosts.isEmpty {
                    ContentUnavailableView {
                        Label("没有匹配的机器", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("试试其他关键字。")
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(model.dockerHosts) { host in
                            DockerHostCard(host: host, runtime: model.runtime(for: host.id)) {
                                model.openDocker(host)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(HostpaneTheme.page)
        .navigationTitle("Docker")
        .searchable(text: $model.dockerSearch, placement: .toolbar, prompt: "搜索")
    }
}

private struct DockerHostCard: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    let runtime: HostRuntime
    var onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                DistroBadge(osID: runtime.metrics?.osID ?? "", size: 28)
                Text(host.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                statusBadge
            }
            HStack(spacing: 16) {
                meta(icon: "cpu", text: coresText)
                meta(icon: "memorychip", text: memoryText)
                meta(icon: "internaldrive", text: diskText)
                meta(icon: "clock", text: uptimeText)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider().opacity(0.35)
            HStack {
                stat("引擎", engineText)
                stat("镜像", countText(imageCount))
                stat("运行中", countText(runningCount))
                stat("已停止", countText(stoppedCount))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(hovering ? HostpaneTheme.accent.opacity(0.7) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("打开 Docker") { onOpen() }
            Button("打开终端") { model.openTerminal(host) }
            Button("打开 SFTP") { model.openSFTP(host) }
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
    }

    private var statusColor: Color {
        HostStatusBadge.color(
            reachability: runtime.reachability,
            latency: runtime.latencySeconds,
            showLatency: model.settings.showLatency,
            useColor: model.settings.latencyUsesColor
        )
    }

    private var statusText: String {
        HostStatusBadge.text(
            reachability: runtime.reachability,
            latency: runtime.latencySeconds,
            showLatency: model.settings.showLatency
        )
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

    private var uptimeText: String {
        guard let metrics = runtime.metrics else { return "—" }
        return formatUptime(metrics.uptimeSeconds)
    }

    private var snapshot: DockerSnapshot? { runtime.dockerSnapshot }

    private var engineText: String {
        if let version = snapshot?.engine.version, !version.isEmpty { return version }
        if let version = runtime.metrics?.dockerEngineVersion, !version.isEmpty { return version }
        return "—"
    }

    private var imageCount: Int? {
        if let count = snapshot?.images.count { return count }
        if let metrics = runtime.metrics, metrics.hasDockerEngine { return metrics.dockerImageCount }
        return nil
    }

    private var runningCount: Int? {
        if let count = snapshot?.runningCount { return count }
        if let metrics = runtime.metrics, metrics.hasDockerEngine { return metrics.dockerRunningCount }
        return nil
    }

    private var stoppedCount: Int? {
        if let count = snapshot?.stoppedCount { return count }
        if let metrics = runtime.metrics, metrics.hasDockerEngine { return metrics.dockerStoppedCount }
        return nil
    }

    private func countText(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)"
    }

    private func meta(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text).monospacedDigit()
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

struct DockerHostView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord

    var body: some View {
        let runtime = model.runtime(for: host.id)
        Group {
            if runtime.dockerProgress.cardVisible, runtime.dockerPhase != .idle {
                DockerConnectionInfoView(host: host)
            } else if runtime.dockerPhase == .connected, let snapshot = runtime.dockerSnapshot {
                DockerPanelView(host: host, snapshot: snapshot)
            } else if case .failed(let message) = runtime.dockerPhase {
                ContentUnavailableView {
                    Label("Docker 失败", systemImage: "shippingbox")
                } description: {
                    Text(runtime.lastError ?? message)
                } actions: {
                    Button("重试") { model.restartDocker(host) }
                }
            } else {
                ProgressView("正在打开 Docker…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(HostpaneTheme.page)
        .navigationTitle(host.displayName)
        .toolbar {
            ToolbarItem {
                Button("重新加载") { model.restartDocker(host) }
            }
            ToolbarItem {
                Button("关闭") { model.closeDocker(host) }
            }
        }
        .onAppear {
            switch runtime.dockerPhase {
            case .idle, .failed:
                model.startDocker(host)
            default:
                break
            }
        }
    }
}

struct DockerConnectionInfoView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord

    var body: some View {
        let runtime = model.runtime(for: host.id)
        let progress = runtime.dockerProgress
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(runtime: runtime)
                endpoint
                steps(progress)
                logs(progress)
            }
            .padding(22)
            .frame(maxWidth: 760)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(HostpaneTheme.page)
    }

    private func header(runtime: HostRuntime) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(HostpaneTheme.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                DockerWhaleIcon(size: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName)
                    .font(.headline)
                Text(subtitle(runtime.dockerPhase))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var endpoint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("端点")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(host.username)@\(host.hostname):\(host.port)")
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }

    private func steps(_ progress: DockerConnectionProgress) -> some View {
        HStack(spacing: 8) {
            ForEach(DockerConnectStep.allCases) { step in
                stepChip(step, state: progress.steps[step] ?? .pending)
            }
        }
    }

    private func stepChip(_ step: DockerConnectStep, state: ConnectStepState) -> some View {
        HStack(spacing: 6) {
            switch state {
            case .running:
                ProgressView().controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill")
            case .failed:
                Image(systemName: "xmark.circle.fill")
            case .pending:
                Image(systemName: "circle")
            }
            Text(step.title)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(chipBackground(state), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(chipForeground(state))
    }

    private func chipBackground(_ state: ConnectStepState) -> Color {
        switch state {
        case .running: return HostpaneTheme.accent.opacity(0.12)
        case .done: return Color.green.opacity(0.12)
        case .failed: return Color.red.opacity(0.12)
        case .pending: return Color.secondary.opacity(0.08)
        }
    }

    private func chipForeground(_ state: ConnectStepState) -> Color {
        switch state {
        case .running: return HostpaneTheme.accent
        case .done: return .green
        case .failed: return .red
        case .pending: return .secondary
        }
    }

    private func logs(_ progress: DockerConnectionProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("连接日志")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(progress.logsVisible ? "隐藏" : "显示") {
                    progress.logsVisible.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if progress.logsVisible {
                HStack {
                    Text("\(progress.logs.count) 个事件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sections(progress.logs), id: \.title) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(section.lines) { line in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(HostpaneTheme.accent)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 5)
                                    Text(line.formattedLine)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func sections(_ lines: [ConnectionLogLine]) -> [(title: String, lines: [ConnectionLogLine])] {
        var result: [(title: String, lines: [ConnectionLogLine])] = []
        for line in lines {
            if result.last?.title == line.sectionTitle {
                result[result.count - 1].lines.append(line)
            } else {
                result.append((line.sectionTitle, [line]))
            }
        }
        return result
    }

    private func subtitle(_ phase: ConnectionPhase) -> String {
        switch phase {
        case .connecting: return "正在加载 Docker 数据"
        case .connected: return "已连接"
        case .failed: return "连接失败"
        case .idle: return "未连接"
        }
    }
}

struct DockerPanelView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    let snapshot: DockerSnapshot
    @State private var confirmPruneVolumes = false

    var body: some View {
        @Bindable var runtime = model.runtime(for: host.id)
        VStack(spacing: 0) {
            tabBar(runtime)
            ScrollView {
                Group {
                    switch runtime.dockerTab {
                    case .overview:
                        DockerOverviewView(host: host, snapshot: snapshot)
                    case .containers:
                        DockerContainersView(host: host, snapshot: snapshot)
                    case .compose:
                        DockerSimpleList(
                            title: "Compose",
                            empty: "没有 Compose 项目。",
                            rows: snapshot.compose.map { ($0.name, $0.status, $0.configFiles) }
                        )
                    case .images:
                        DockerImagesView(host: host, snapshot: snapshot)
                    case .volumes:
                        DockerVolumesView(host: host, snapshot: snapshot)
                    case .networks:
                        DockerNetworksView(host: host, snapshot: snapshot)
                    case .events:
                        DockerEventsView(host: host, snapshot: snapshot)
                    }
                }
                .padding(20)
            }
        }
        .background(HostpaneTheme.page)
        .searchable(text: $runtime.dockerContainerQuery, prompt: "搜索")
        .toolbar {
            if runtime.dockerTab == .containers {
                ToolbarItem {
                    Menu {
                        ForEach(DockerContainerSort.allCases) { sort in
                            Button(sort.title) { runtime.dockerContainerSort = sort }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .help("排序")
                }
            }
            if runtime.dockerTab == .volumes {
                ToolbarItem {
                    Button {
                        confirmPruneVolumes = true
                    } label: {
                        Label("清理卷", systemImage: "wrench.and.screwdriver")
                    }
                    .help("清理未使用的卷")
                    .disabled(runtime.dockerBusy)
                }
            }
        }
        .alert("清理未使用的卷？", isPresented: $confirmPruneVolumes) {
            Button("清理", role: .destructive) {
                Task { await model.dockerPruneVolumes(host) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会删除当前没有容器使用的卷，不可恢复。")
        }
        .navigationDestination(item: $runtime.dockerSelectedContainerID) { id in
            DockerContainerDetailView(host: host, containerName: id)
        }
        .navigationDestination(item: $runtime.dockerSelectedImageID) { id in
            DockerImageDetailView(host: host, imageID: id)
        }
        .navigationDestination(item: $runtime.dockerSelectedVolumeID) { id in
            DockerVolumeDetailView(host: host, volumeName: id)
        }
        .navigationDestination(item: $runtime.dockerSelectedNetworkID) { id in
            DockerNetworkDetailView(host: host, networkName: id)
        }
        .safeAreaInset(edge: .bottom) {
            if !runtime.dockerStatus.isEmpty {
                Text(runtime.dockerStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
        }
    }

    private func tabBar(_ runtime: HostRuntime) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DockerTab.allCases) { tab in
                    Button {
                        runtime.dockerTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    runtime.dockerTab == tab
                                        ? HostpaneTheme.accent.opacity(0.16)
                                        : Color.secondary.opacity(0.08)
                                )
                            )
                            .foregroundStyle(runtime.dockerTab == tab ? HostpaneTheme.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }
}

private struct DockerOverviewView: View {
    let host: HostRecord
    let snapshot: DockerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            engineHeader
            summaryRow
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        statusCard
                        diskCard
                    }
                    resourceColumn
                }
                VStack(spacing: 16) {
                    statusCard
                    diskCard
                    resourceColumn
                }
            }
        }
    }

    private var engineHeader: some View {
        InspectCard {
            HStack(alignment: .center, spacing: 14) {
                DockerWhaleIcon(size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Docker 引擎")
                            .font(.headline)
                        Text("已连接")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HostpaneTheme.online)
                    }
                    Text("v\(snapshot.engine.version)")
                        .font(.title2.weight(.semibold))
                    Text(snapshot.engine.platformLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !snapshot.engine.socket.isEmpty {
                    Text("Socket: \(snapshot.engine.socket)")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(HostpaneTheme.online.opacity(0.12)))
                        .foregroundStyle(HostpaneTheme.online)
                }
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            summaryTile("容器", "\(snapshot.containers.count)", "\(snapshot.pausedCount) 个已暂停 · \(snapshot.stoppedCount) 个已停止", "shippingbox")
            summaryTile("运行中", "\(snapshot.runningCount)", "活动容器", "play.fill")
            summaryTile("镜像", "\(snapshot.images.count)", "\(snapshot.danglingImageCount) 个悬空镜像", "internaldrive")
            summaryTile(
                "可回收",
                formatBytes(snapshot.disk.reclaimableBytes),
                snapshot.disk.reclaimableShare.map { "占 Docker 数据的 \(formatPercent($0))" } ?? "可清理空间",
                "trash"
            )
        }
    }

    private func summaryTile(_ title: String, _ value: String, _ detail: String, _ icon: String) -> some View {
        InspectCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title.monospacedDigit().weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusCard: some View {
        InspectCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("容器状态")
                    .font(.headline)
                    .foregroundStyle(HostpaneTheme.online)
                Text("\(snapshot.containers.count)")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                + Text("  总计")
                    .foregroundStyle(.secondary)
                stackedBar
                HStack {
                    legend(HostpaneTheme.online, "运行中", snapshot.runningCount)
                    legend(HostpaneTheme.connecting, "已暂停", snapshot.pausedCount)
                    legend(.secondary, "已停止", snapshot.stoppedCount)
                    legend(HostpaneTheme.loadMedium, "其他", snapshot.otherCount)
                }
                .font(.caption)
            }
        }
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            let total = max(snapshot.containers.count, 1)
            HStack(spacing: 0) {
                bar(HostpaneTheme.online, snapshot.runningCount, total, geo.size.width)
                bar(HostpaneTheme.connecting, snapshot.pausedCount, total, geo.size.width)
                bar(Color.secondary.opacity(0.45), snapshot.stoppedCount, total, geo.size.width)
                bar(HostpaneTheme.loadMedium, snapshot.otherCount, total, geo.size.width)
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }

    private func bar(_ color: Color, _ count: Int, _ total: Int, _ width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: width * CGFloat(count) / CGFloat(total))
    }

    private func legend(_ color: Color, _ title: String, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).foregroundStyle(.secondary)
            Text("\(count)").monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var diskCard: some View {
        InspectCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("磁盘用量")
                        .font(.headline)
                        .foregroundStyle(HostpaneTheme.online)
                    Spacer()
                    Text("Docker 数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(formatBytes(snapshot.disk.totalBytes))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                diskBar
                HStack {
                    diskLegend(HostpaneTheme.docker, "镜像", snapshot.disk.images.sizeBytes)
                    diskLegend(HostpaneTheme.online, "容器", snapshot.disk.containers.sizeBytes)
                    diskLegend(Color.purple, "卷", snapshot.disk.volumes.sizeBytes)
                    diskLegend(HostpaneTheme.cpuUser, "构建缓存", snapshot.disk.buildCache.sizeBytes)
                }
                .font(.caption)
                HStack {
                    Text("可回收")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatBytes(snapshot.disk.reclaimableBytes))
                        .foregroundStyle(HostpaneTheme.loadMedium)
                        .fontWeight(.semibold)
                }
                .font(.caption)
            }
        }
    }

    private var diskBar: some View {
        GeometryReader { geo in
            let total = max(snapshot.disk.totalBytes, 1)
            HStack(spacing: 0) {
                diskSeg(HostpaneTheme.docker, snapshot.disk.images.sizeBytes, total, geo.size.width)
                diskSeg(HostpaneTheme.online, snapshot.disk.containers.sizeBytes, total, geo.size.width)
                diskSeg(Color.purple, snapshot.disk.volumes.sizeBytes, total, geo.size.width)
                diskSeg(HostpaneTheme.cpuUser, snapshot.disk.buildCache.sizeBytes, total, geo.size.width)
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }

    private func diskSeg(_ color: Color, _ bytes: UInt64, _ total: UInt64, _ width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: width * CGFloat(bytes) / CGFloat(total))
    }

    private func diskLegend(_ color: Color, _ title: String, _ bytes: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).foregroundStyle(.secondary)
            }
            Text(formatBytes(bytes)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resourceColumn: some View {
        VStack(spacing: 16) {
            InspectCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("实时资源")
                            .font(.headline)
                            .foregroundStyle(HostpaneTheme.cpuUser)
                        Spacer()
                        Text("\(snapshot.runningCount) 个实时容器")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        resourceMeter(
                            title: "容器 CPU",
                            value: String(format: "%.1f%%", snapshot.totalCPURatio * 100),
                            ratio: min(snapshot.totalCPURatio, 1),
                            detail: "涵盖 \(snapshot.runningCount) 个容器",
                            color: HostpaneTheme.cpuUser
                        )
                        resourceMeter(
                            title: "容器内存",
                            value: formatBytes(snapshot.totalMemoryBytes),
                            ratio: snapshot.containers.first.flatMap { item in
                                item.memoryLimitBytes > 0
                                    ? Double(snapshot.totalMemoryBytes) / Double(max(item.memoryLimitBytes, 1))
                                    : nil
                            } ?? min(Double(snapshot.totalMemoryBytes) / 1_073_741_824, 1),
                            detail: "占用中",
                            color: Color.purple
                        )
                    }
                }
            }
            InspectCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("资源占用最高项")
                        .font(.headline)
                    Text("CPU")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HostpaneTheme.cpuUser)
                    ForEach(snapshot.topCPU.prefix(3)) { item in
                        rankedRow(item.name, String(format: "%.1f%%", item.cpuRatio * 100), item.cpuRatio, HostpaneTheme.cpuUser)
                    }
                    Text("内存")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.purple)
                        .padding(.top, 6)
                    ForEach(snapshot.topMemory.prefix(3)) { item in
                        rankedRow(item.name, formatBytes(item.memoryUsedBytes), item.memoryRatio, Color.purple)
                    }
                }
            }
            InspectCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("引擎详情")
                        .font(.headline)
                    detail("版本", snapshot.engine.version)
                    detail("API 版本", snapshot.engine.apiVersion)
                    detail("跟随系统", snapshot.engine.platformLine)
                    detail("Context", snapshot.engine.context)
                }
            }
        }
    }

    private func resourceMeter(title: String, value: String, ratio: Double, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(max(ratio, 0), 1))
                }
            }
            .frame(height: 8)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func rankedRow(_ name: String, _ value: String, _ ratio: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .lineLimit(1)
                Spacer()
                Text(value)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(max(ratio, 0.02), 1))
                }
            }
            .frame(height: 6)
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .textSelection(.enabled)
        }
        .font(.caption)
    }
}

private struct DockerSimpleList: View {
    let title: String
    let empty: String
    let rows: [(String, String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            if rows.isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    InspectCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.0)
                                .font(.headline)
                            if !row.1.isEmpty {
                                Text(row.1)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !row.2.isEmpty {
                                Text(row.2)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }
}
