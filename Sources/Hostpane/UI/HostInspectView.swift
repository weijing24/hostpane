import SwiftUI
import HostpaneCore

struct HostInspectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let host: HostRecord
    var showsChrome: Bool = true
    @State private var detail: InspectDetail?
    @State private var processSort = ProcessSort()
    @State private var memoryHover: MemorySliceKind?
    @State private var stubMessage: String?
    @State private var choosingInterface = false
    @State private var choosingVolume = false

    private var record: HostRecord {
        model.hosts.first(where: { $0.id == host.id }) ?? host
    }

    var body: some View {
        let runtime = model.runtime(for: host.id)
        DashboardScrollBackdrop(
            light: model.settings.dashboardBackgroundLight,
            dark: model.settings.dashboardBackgroundDark,
            isDark: useDarkBackground,
            inset: showsChrome ? 24 : 16
        ) {
            VStack(alignment: .leading, spacing: 16) {
                header(runtime)
                statusBoard(runtime)
            }
        }
        .navigationTitle(showsChrome ? record.displayName : "")
        .toolbar(showsChrome ? .automatic : .hidden)
        .toolbar {
          if showsChrome {
            ToolbarItemGroup {
                Button {
                    model.openTerminal(record)
                } label: {
                    Image(systemName: "terminal")
                }
                .help("终端")
                Button {
                    model.openSFTP(record)
                } label: {
                    Image(systemName: "folder")
                }
                .help("SFTP")
                Button {
                    model.openDocker(record)
                } label: {
                    DockerWhaleIcon(size: 14)
                }
                .help("Docker")
            }
            ToolbarItem {
                Menu {
                    Button {
                        model.updateHost(record.id) { $0.hideAddress.toggle() }
                    } label: {
                        Label(
                            record.hideAddress ? "显示 IP 信息" : "隐藏 IP 信息",
                            systemImage: record.hideAddress ? "eye.slash" : "eye"
                        )
                    }
                    Button("设置默认网络接口", systemImage: "wifi") {
                        choosingInterface = true
                    }
                    Button("设置默认卷", systemImage: "internaldrive") {
                        choosingVolume = true
                    }
                    Divider()
                    Button("编辑机器") { model.beginEditHost(record) }
                    Button("重新检测") { model.startMonitor(record, restart: true) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .help("更多")
                .menuIndicator(.visible)
            }
          }
        }
        .confirmationDialog("设置默认网络接口", isPresented: $choosingInterface, titleVisibility: .visible) {
            Button("自动") {
                model.updateHost(record.id) { $0.defaultInterface = nil }
            }
            ForEach(runtime.metrics?.interfaces ?? []) { iface in
                Button(interfaceLabel(iface)) {
                    model.updateHost(record.id) { $0.defaultInterface = iface.name }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("设置默认卷", isPresented: $choosingVolume, titleVisibility: .visible) {
            Button("自动（最大本地卷）") {
                model.updateHost(record.id) { $0.defaultMount = nil }
            }
            ForEach(runtime.metrics?.localDisks ?? []) { disk in
                Button(volumeLabel(disk)) {
                    model.updateHost(record.id) { $0.defaultMount = disk.mount }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert(
            "还没接上",
            isPresented: Binding(
                get: { stubMessage != nil },
                set: { if !$0 { stubMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { stubMessage = nil }
        } message: {
            Text(stubMessage ?? "")
        }
        .sheet(item: $detail) { item in
            switch item {
            case .processes:
                ProcessDetailSheet(hostID: host.id)
            case .network:
                NetworkDetailSheet(hostID: host.id)
            case .storage:
                StorageDetailSheet(hostID: host.id)
            }
        }
        .onAppear { model.startMonitor(host) }
    }

    private var useDarkBackground: Bool {
        switch model.settings.appearance {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            return colorScheme == .dark || model.isDarkAppearance
        }
    }

    private func statusBoard(_ runtime: HostRuntime) -> some View {
        let layout = model.settings.statusLayout.normalized()
        let slots = StatusLayoutGrid.slots(for: layout)
        return StatusBoardLayout(columns: layout.columns, slots: slots) {
            ForEach(slots) { slot in
                statusCard(slot.kind, runtime: runtime)
            }
        }
    }

    @ViewBuilder
    private func statusCard(_ kind: StatusCardKind, runtime: HostRuntime) -> some View {
        switch kind {
        case .cpu:
            cpuCard(runtime)
        case .load:
            loadCard(runtime, expands: true)
        case .processes:
            processCard(runtime, expands: true)
        case .memory:
            memoryCard(runtime, expands: true)
        case .network:
            networkCard(runtime)
        case .storage:
            storageCard(runtime)
        case .docker:
            dockerSection(runtime.metrics?.containers ?? [])
        }
    }

    @ViewBuilder
    private func header(_ runtime: HostRuntime) -> some View {
        HStack(alignment: .center, spacing: 16) {
            DistroBadge(osID: runtime.metrics?.osID ?? "", size: 64)
            VStack(alignment: .leading, spacing: 8) {
                Text(record.displayName)
                    .font(.title.weight(.semibold))
                Text(runtime.metrics?.osDisplayName ?? "Linux")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HostpaneTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(HostpaneTheme.accent.opacity(0.14))
                    )
                if !runtime.isOnline, let error = runtime.lastError, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 12)
            RingMeter(
                title: "CPU",
                ratio: runtime.metrics?.cpuUsage,
                color: HostpaneTheme.usageColor(runtime.metrics?.cpuUsage),
                size: 56
            )
            .frame(width: 76)
            RingMeter(
                title: "RAM",
                ratio: runtime.metrics?.memoryUsedRatio,
                color: HostpaneTheme.usageColor(runtime.metrics?.memoryUsedRatio),
                size: 56
            )
            .frame(width: 76)
            RingMeter(
                title: "DISK",
                ratio: runtime.metrics?.preferredDisk(mount: record.defaultMount)?.usedRatio,
                color: HostpaneTheme.usageColor(
                    runtime.metrics?.preferredDisk(mount: record.defaultMount)?.usedRatio
                ),
                size: 56
            )
            .frame(width: 76)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func cpuCard(_ runtime: HostRuntime) -> some View {
        let metrics = runtime.metrics
        InspectCard(expandsVertically: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("CPU 利用率", systemImage: "cpu")
                        .font(.headline)
                        .foregroundStyle(HostpaneTheme.cpuUser)
                    Spacer()
                    Text(metrics?.cpuUsage.map(formatPercent) ?? "—")
                        .font(.title.monospacedDigit().weight(.semibold))
                }
                if let modelName = metrics?.cpuModel, !modelName.isEmpty {
                    Text(modelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let cores = metrics?.cores, !cores.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(cores) { core in
                            HStack(spacing: 8) {
                                Text("\(core.index)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, alignment: .trailing)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.secondary.opacity(0.12))
                                        Capsule()
                                            .fill(HostpaneTheme.cpuRing)
                                            .frame(width: geo.size.width * min(max(core.usage ?? 0, 0), 1))
                                    }
                                }
                                .frame(height: 10)
                                Text(core.usage.map(formatPercent) ?? "—")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                }
                if let times = metrics?.cpuTimes {
                    HStack(spacing: 16) {
                        legend("核心", metrics.flatMap { $0.cpuCores > 0 ? "\($0.cpuCores)" : nil } ?? "—")
                        Spacer()
                        cpuLegend("User", times.user, HostpaneTheme.cpuUser)
                        cpuLegend("System", times.system, HostpaneTheme.cpuSystem)
                        cpuLegend("Nice", times.nice, HostpaneTheme.cpuNice)
                        cpuLegend("IOWait", times.iowait, HostpaneTheme.cpuIOWait)
                        cpuLegend("Steal", times.steal, HostpaneTheme.cpuSteal)
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func loadCard(_ runtime: HostRuntime, expands: Bool = false) -> some View {
        InspectCard(expandsVertically: expands) {
            VStack(alignment: .leading, spacing: 10) {
                Label("CPU 负载", systemImage: "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(HostpaneTheme.loadFifteen)
                LoadChart(points: runtime.loadHistory)
                    .frame(minHeight: 168, maxHeight: expands ? .infinity : nil)
                    .padding(.vertical, 2)
                HStack {
                    loadKey(HostpaneTheme.loadOne, "1m")
                    loadKey(HostpaneTheme.loadFive, "5m")
                    loadKey(HostpaneTheme.loadFifteen, "15m")
                }
                HStack {
                    Text("当前负载")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let load = runtime.metrics?.loadAverage {
                        Text(String(format: "%.2f / %.2f / %.2f", load.0, load.1, load.2))
                            .font(.caption.monospacedDigit().weight(.medium))
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: expands ? .infinity : nil, alignment: .top)
        }
    }

    @ViewBuilder
    private func processCard(_ runtime: HostRuntime, expands: Bool = false) -> some View {
        InspectCard(expandsVertically: expands) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    detail = .processes
                } label: {
                    InspectSectionHeader(
                        title: "进程",
                        systemImage: "waveform.path.ecg",
                        color: HostpaneTheme.offline,
                        showsChevron: true
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let processes = runtime.metrics?.processes, !processes.isEmpty {
                    ProcessTableView(processes: processes, sort: $processSort, limit: 14)
                        .frame(maxHeight: expands ? .infinity : nil, alignment: .top)
                } else {
                    Text(runtime.isOnline ? "暂无进程数据" : "离线时不采集进程")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                }
            }
            .frame(maxHeight: expands ? .infinity : nil, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: expands ? .infinity : nil, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { detail = .processes }
    }

    @ViewBuilder
    private func memoryCard(_ runtime: HostRuntime, expands: Bool = false) -> some View {
        InspectCard(expandsVertically: expands) {
            VStack(alignment: .leading, spacing: 14) {
                Label("内存利用", systemImage: "memorychip")
                    .font(.headline)
                    .foregroundStyle(HostpaneTheme.memUsed)
                if let metrics = runtime.metrics, metrics.memoryTotalBytes > 0 {
                    HStack(alignment: .center, spacing: 24) {
                        MemoryDonut(metrics: metrics, hovered: $memoryHover)
                        VStack(alignment: .leading, spacing: 12) {
                            memoryLegend(
                                kind: .used,
                                bytes: metrics.memoryBreakdownUsedBytes,
                                total: metrics.memoryTotalBytes
                            )
                            memoryLegend(
                                kind: .cached,
                                bytes: metrics.memoryCachedBytes,
                                total: metrics.memoryTotalBytes
                            )
                            memoryLegend(
                                kind: .free,
                                bytes: metrics.memoryFreeBytes,
                                total: metrics.memoryTotalBytes
                            )
                        }
                        Spacer()
                    }
                    .frame(maxHeight: expands ? .infinity : nil)
                    Divider()
                    HStack {
                        Text("交换空间")
                            .font(.caption)
                        Spacer()
                        if metrics.swapTotalBytes == 0 {
                            Text("N/A")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(formatInspectBytes(metrics.swapUsedBytes)) / \(formatInspectBytes(metrics.swapTotalBytes))")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    if metrics.swapTotalBytes > 0 {
                        StorageBar(ratio: metrics.swapUsedRatio, color: HostpaneTheme.memUsed)
                    }
                } else {
                    Text("还没有内存样本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: expands ? .infinity : nil, alignment: .top)
        }
    }

    @ViewBuilder
    private func networkCard(_ runtime: HostRuntime) -> some View {
        InspectCard(expandsVertically: true) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    detail = .network
                } label: {
                    InspectSectionHeader(
                        title: "网络使用情况",
                        systemImage: "wifi",
                        color: HostpaneTheme.netUp,
                        showsChevron: true
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let iface = runtime.metrics?.preferredInterface(named: record.defaultInterface) {
                    NetworkUsageBlock(iface: iface, hideAddress: record.hideAddress)
                } else {
                    Text("还没有网络样本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { detail = .network }
    }

    @ViewBuilder
    private func storageCard(_ runtime: HostRuntime) -> some View {
        InspectCard(expandsVertically: true) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    detail = .storage
                } label: {
                    InspectSectionHeader(
                        title: "存储",
                        systemImage: "internaldrive",
                        color: HostpaneTheme.online,
                        showsChevron: true
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let disk = runtime.metrics?.preferredDisk(mount: record.defaultMount) {
                    StorageUsageBlock(disk: disk, showsIO: true)
                } else {
                    Text("还没有磁盘样本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { detail = .storage }
    }

    @ViewBuilder
    private func dockerSection(_ containers: [ContainerSample]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                DockerWhaleIcon(size: 20)
                Text("Docker")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HostpaneTheme.docker)
                Text("正在运行的容器")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(containers.count)")
                    .foregroundStyle(.secondary)
            }
            if !containers.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                    ForEach(containers) { container in
                        containerCard(container)
                    }
                }
            }
        }
    }

    private func containerCard(_ container: ContainerSample) -> some View {
        InspectCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(container.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if !container.status.isEmpty {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(HostpaneTheme.online)
                                .frame(width: 7, height: 7)
                            Text(container.status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                HStack(alignment: .center, spacing: 8) {
                    RingMeter(title: "CPU", ratio: container.cpuRatio, color: HostpaneTheme.cpuRing, size: 58)
                    RingMeter(title: "RAM", ratio: container.memoryRatio, color: HostpaneTheme.memoryRing, size: 58)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("网络").font(.caption2).foregroundStyle(.secondary)
                        labeledRate("↑", container.netTransmitBytesPerSecond)
                        labeledRate("↓", container.netReceiveBytesPerSecond)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("磁盘").font(.caption2).foregroundStyle(.secondary)
                        labeledRate("读", container.blockReadBytesPerSecond)
                        labeledRate("写", container.blockWriteBytesPerSecond)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func cpuLegend(_ title: String, _ ratio: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .foregroundStyle(.secondary)
            Text(formatPercent(ratio))
                .monospacedDigit()
        }
    }

    private func legend(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private func loadKey(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 10, height: 3)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func memoryLegend(kind: MemorySliceKind, bytes: UInt64, total: UInt64) -> some View {
        let active = memoryHover == kind
        return HStack(spacing: 8) {
            Circle().fill(kind.color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(formatInspectBytes(bytes))
                    .font(.subheadline.weight(.semibold))
                if total > 0 {
                    Text("\(formatPercent(Double(bytes) / Double(total))) \(kind.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(memoryHover == nil || active ? 1 : 0.45)
        .scaleEffect(active ? 1.04 : 1)
        .contentShape(Rectangle())
        .onHover { inside in
            let update = {
                if inside {
                    memoryHover = kind
                } else if memoryHover == kind {
                    memoryHover = nil
                }
            }
            if model.settings.reduceStatusMotion {
                update()
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    update()
                }
            }
        }
    }

    private func labeledRate(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            Text(value.map(formatCompactRate) ?? "—")
                .font(.callout.monospacedDigit().weight(.semibold))
        }
    }

    private func interfaceLabel(_ iface: InterfaceSample) -> String {
        if record.hideAddress {
            return iface.name
        }
        if let cidr = iface.ipv4CIDR, !cidr.isEmpty {
            return "\(iface.name)  \(cidr)"
        }
        return iface.name
    }

    private func volumeLabel(_ disk: DiskSample) -> String {
        "\(disk.mount)  \(formatInspectBytes(disk.totalBytes))"
    }
}

private struct StatusBoardLayout: Layout {
    var columns: Int
    var slots: [StatusGridSlot]
    var spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 720
        let rows = rowHeights(totalWidth: width, subviews: subviews)
        let height = rows.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rowHeights(totalWidth: bounds.width, subviews: subviews)
        let metrics = columnMetrics(totalWidth: bounds.width)
        for index in subviews.indices where index < slots.count {
            let frame = frame(for: slots[index], rows: rows, metrics: metrics, origin: bounds.origin)
            subviews[index].place(
                at: CGPoint(x: frame.minX, y: frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func columnMetrics(totalWidth: CGFloat) -> (width: CGFloat, stride: CGFloat) {
        let count = CGFloat(max(columns, 1))
        let width = max((totalWidth - spacing * (count - 1)) / count, 1)
        return (width, width + spacing)
    }

    private func rowHeights(totalWidth: CGFloat, subviews: Subviews) -> [CGFloat] {
        let rowCount = slots.map { $0.row + $0.height }.max() ?? 0
        guard rowCount > 0 else { return [] }
        var rows = Array(repeating: CGFloat(0), count: rowCount)
        let metrics = columnMetrics(totalWidth: totalWidth)
        for index in subviews.indices where index < slots.count {
            let slot = slots[index]
            let cardWidth = metrics.width * CGFloat(slot.width) + spacing * CGFloat(max(slot.width - 1, 0))
            let ideal = subviews[index].sizeThatFits(ProposedViewSize(width: cardWidth, height: nil)).height
            let share = ideal / CGFloat(max(slot.height, 1))
            let end = min(slot.row + slot.height, rows.count)
            guard slot.row < end else { continue }
            for row in slot.row..<end {
                rows[row] = max(rows[row], share)
            }
        }
        return rows
    }

    private func frame(
        for slot: StatusGridSlot,
        rows: [CGFloat],
        metrics: (width: CGFloat, stride: CGFloat),
        origin: CGPoint
    ) -> CGRect {
        let x = origin.x + metrics.stride * CGFloat(slot.column)
        var y = origin.y
        for row in 0..<min(slot.row, rows.count) {
            y += rows[row] + spacing
        }
        let end = min(slot.row + slot.height, rows.count)
        var height = CGFloat(0)
        if slot.row < end {
            for row in slot.row..<end {
                height += rows[row]
            }
            height += spacing * CGFloat(end - slot.row - 1)
        }
        let width = metrics.width * CGFloat(slot.width) + spacing * CGFloat(max(slot.width - 1, 0))
        return CGRect(x: x, y: y, width: width, height: max(height, 1))
    }
}
