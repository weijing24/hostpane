import SwiftUI
import HostpaneCore

struct DockerContainersView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    let snapshot: DockerSnapshot

    var body: some View {
        let runtime = model.runtime(for: host.id)
        VStack(alignment: .leading, spacing: 14) {
            filterRow(runtime)
            if filtered(runtime).isEmpty {
                ContentUnavailableView {
                    Label("没有容器", systemImage: "shippingbox")
                } description: {
                    Text("试试其他筛选，或清空搜索。")
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(filtered(runtime)) { item in
                        DockerContainerCard(item: item) {
                            runtime.dockerSelectedContainerID = item.id
                        }
                        .contextMenu { containerMenu(item) }
                    }
                }
            }
        }
    }

    private func filterRow(_ runtime: HostRuntime) -> some View {
        HStack(spacing: 8) {
            ForEach(DockerContainerFilter.allCases) { filter in
                Button {
                    runtime.dockerContainerFilter = filter
                } label: {
                    Text(filter.title)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                runtime.dockerContainerFilter == filter
                                    ? HostpaneTheme.accent.opacity(0.16)
                                    : Color.secondary.opacity(0.08)
                            )
                        )
                        .foregroundStyle(
                            runtime.dockerContainerFilter == filter ? HostpaneTheme.accent : .secondary
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func filtered(_ runtime: HostRuntime) -> [DockerContainer] {
        var rows = snapshot.containers
        switch runtime.dockerContainerFilter {
        case .all: break
        case .running: rows = rows.filter(\.isRunning)
        case .stopped: rows = rows.filter(\.isStopped)
        case .paused: rows = rows.filter(\.isPaused)
        }
        let query = runtime.dockerContainerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            rows = rows.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.image.localizedCaseInsensitiveContains(query)
                    || $0.composeLine.localizedCaseInsensitiveContains(query)
            }
        }
        switch runtime.dockerContainerSort {
        case .name: rows.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .status: rows.sort { $0.status.localizedCompare($1.status) == .orderedAscending }
        case .cpu: rows.sort { $0.cpuRatio > $1.cpuRatio }
        case .memory: rows.sort { $0.memoryUsedBytes > $1.memoryUsedBytes }
        }
        return rows
    }

    @ViewBuilder
    private func containerMenu(_ item: DockerContainer) -> some View {
        Button("启动") { Task { await model.dockerAction(host, "start", name: item.name) } }
        Button("停止") { Task { await model.dockerAction(host, "stop", name: item.name) } }
        Button("重启") { Task { await model.dockerAction(host, "restart", name: item.name) } }
        Button("暂停") { Task { await model.dockerAction(host, "pause", name: item.name) } }
        Button("恢复") { Task { await model.dockerAction(host, "unpause", name: item.name) } }
        Divider()
        Button("删除", role: .destructive) {
            Task { await model.dockerAction(host, "rm -f", name: item.name) }
        }
    }
}

private struct DockerContainerCard: View {
    let item: DockerContainer
    var onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(HostpaneTheme.docker)
                    Text(item.name)
                        .font(.headline)
                        .foregroundStyle(HostpaneTheme.docker)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.isRunning ? HostpaneTheme.online : Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(item.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if item.isHealthy {
                        Text("健康")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(HostpaneTheme.online.opacity(0.16)))
                            .foregroundStyle(HostpaneTheme.online)
                    }
                }
                Text(item.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !item.composeLine.isEmpty {
                    Label(item.composeLine, systemImage: "square.stack.3d.up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if item.isRunning || item.isPaused {
                    Divider().opacity(0.35)
                    HStack(alignment: .center, spacing: 8) {
                        RingMeter(
                            title: "CPU",
                            ratio: min(item.cpuRatio, 1),
                            color: HostpaneTheme.cpuRing,
                            size: 52,
                            titleOnTop: true
                        )
                        RingMeter(
                            title: "RAM",
                            ratio: item.memoryRatio,
                            color: HostpaneTheme.memoryRing,
                            size: 52,
                            titleOnTop: true
                        )
                        ioColumn(
                            title: "网络",
                            up: item.netTransmitBytes,
                            down: item.netReceiveBytes,
                            upIcon: "arrow.up.circle",
                            downIcon: "arrow.down.circle"
                        )
                        ioColumn(
                            title: "Block IO",
                            up: item.blockReadBytes,
                            down: item.blockWriteBytes,
                            upIcon: "r.circle",
                            downIcon: "w.circle"
                        )
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(hovering ? HostpaneTheme.docker.opacity(0.45) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private func ioColumn(title: String, up: UInt64, down: UInt64, upIcon: String, downIcon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            labeled(upIcon, up)
            labeled(downIcon, down)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeled(_ icon: String, _ bytes: UInt64) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatInspectBytes(bytes))
                .font(.subheadline.monospacedDigit().weight(.semibold))
        }
    }
}

struct DockerContainerDetailView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    let containerName: String
    @State private var textKind: DockerTextKind?
    @State private var envExpanded = false

    var body: some View {
        let runtime = model.runtime(for: host.id)
        let item = runtime.dockerSnapshot?.containers.first { $0.id == containerName || $0.name == containerName }
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: 22) {
                    infoSection(item)
                    statsSection(item, runtime: runtime)
                    if !item.health.isEmpty {
                        healthSection(item)
                    }
                    networkSection(item)
                    storageSection(item)
                    envSection(item)
                    actionsSection(item)
                    detailsSection
                }
                .padding(24)
                .frame(maxWidth: 820, alignment: .leading)
            } else {
                ContentUnavailableView("找不到这个容器", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .background(HostpaneTheme.page)
        .navigationTitle(item?.name ?? containerName)
        .navigationDestination(item: $textKind) { kind in
            DockerTextPage(host: host, containerName: containerName, kind: kind)
        }
        .task {
            await model.refreshDockerContainerInspect(host, name: containerName)
        }
    }

    private func infoSection(_ item: DockerContainer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("容器信息", systemImage: "info.circle")
                .font(.headline)
            VStack(spacing: 0) {
                infoRow("名称", item.name)
                infoRow("ID", item.shortID)
                infoRow("镜像", item.image)
                infoRow("状态", item.status, dot: item.isRunning ? HostpaneTheme.online : .secondary)
                infoRow("创建于", formatDockerCreated(item.created))
                infoRow("命令", item.command.isEmpty ? "—" : item.command, monospaced: true)
                infoRow("重启策略", item.restartPolicy.isEmpty ? "—" : item.restartPolicy)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
        }
    }

    private func statsSection(_ item: DockerContainer, runtime: HostRuntime) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("实时统计信息", systemImage: "waveform.path.ecg")
                .font(.headline)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 8) {
                    RingMeter(
                        title: "CPU",
                        ratio: min(item.cpuRatio, 1),
                        color: HostpaneTheme.cpuRing,
                        size: 64,
                        titleOnTop: true
                    )
                    RingMeter(
                        title: "RAM",
                        ratio: item.memoryRatio,
                        color: HostpaneTheme.memoryRing,
                        size: 64,
                        titleOnTop: true
                    )
                    ioBlock("网络", item.netTransmitBytes, item.netReceiveBytes, "arrow.up.circle", "arrow.down.circle")
                    ioBlock("Block IO", item.blockReadBytes, item.blockWriteBytes, "r.circle", "w.circle")
                }
                sparkline(
                    title: "CPU",
                    points: runtime.dockerStatHistory[item.name] ?? [],
                    value: { $0.cpuRatio * 100 },
                    current: String(format: "%.1f%%", item.cpuRatio * 100),
                    color: HostpaneTheme.docker
                )
                sparkline(
                    title: "内存",
                    points: runtime.dockerStatHistory[item.name] ?? [],
                    value: { $0.memoryRatio * 100 },
                    current: String(format: "%.1f%%", item.memoryRatio * 100),
                    color: HostpaneTheme.online
                )
                HStack {
                    Text("内存")
                    Spacer()
                    Text("\(formatInspectBytes(item.memoryUsedBytes)) / \(formatInspectBytes(item.memoryLimitBytes))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                HStack {
                    Text("PID")
                    Spacer()
                    Text(item.pid == 0 ? "—" : "\(item.pid)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
        }
    }

    private func healthSection(_ item: DockerContainer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("健康检查", systemImage: "heart")
                .font(.headline)
            HStack {
                Text("状态")
                Spacer()
                Text(item.isHealthy ? "健康" : item.health)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill((item.isHealthy ? HostpaneTheme.online : HostpaneTheme.loadMedium).opacity(0.16))
                    )
                    .foregroundStyle(item.isHealthy ? HostpaneTheme.online : HostpaneTheme.loadMedium)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
        }
    }

    private func networkSection(_ item: DockerContainer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("网络", systemImage: "globe")
                .font(.headline)
            HStack {
                Text(item.networkMode.isEmpty ? "—" : item.networkMode)
                    .font(.body.monospaced())
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
        }
    }

    private func storageSection(_ item: DockerContainer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("存储", systemImage: "internaldrive")
                .font(.headline)
            if item.mounts.isEmpty {
                Text("没有挂载。")
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor))
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(item.mounts) { mount in
                        HStack(spacing: 8) {
                            Text(mount.source)
                                .font(.caption.monospaced())
                                .foregroundStyle(HostpaneTheme.docker)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(HostpaneTheme.docker.opacity(0.12)))
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(.secondary)
                            Text(mount.destination)
                                .font(.caption.monospaced())
                                .foregroundStyle(HostpaneTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(HostpaneTheme.accent.opacity(0.12)))
                            Spacer()
                            Text(mount.readOnly ? "ro" : "rw")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.pink.opacity(0.18)))
                                .foregroundStyle(.pink)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        if mount.id != item.mounts.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
            }
        }
    }

    private func envSection(_ item: DockerContainer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("环境", systemImage: "list.bullet.rectangle")
                .font(.headline)
            DisclosureGroup(isExpanded: $envExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.env, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("\(item.env.count) 个变量")
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
        }
    }

    private func actionsSection(_ item: DockerContainer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("操作", systemImage: "hammer")
                .font(.headline)
            VStack(spacing: 0) {
                actionRow("停止", "stop.circle") { Task { await model.dockerAction(host, "stop", name: item.name) } }
                actionRow("重启", "arrow.clockwise") {
                    Task { await model.dockerAction(host, "restart", name: item.name) }
                }
                actionRow("暂停", "pause.circle") { Task { await model.dockerAction(host, "pause", name: item.name) } }
                actionRow("终止", "bolt.circle") { Task { await model.dockerAction(host, "kill", name: item.name) } }
                actionRow("删除", "trash", destructive: true) {
                    Task { await model.dockerAction(host, "rm -f", name: item.name) }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("详情", systemImage: "doc.text")
                .font(.headline)
            VStack(spacing: 0) {
                detailRow("日志", "text.alignleft", .logs)
                detailRow("进程", "list.bullet", .processes)
                detailRow("检查", "eye", .inspect)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
        }
    }

    private func infoRow(_ title: String, _ value: String, dot: Color? = nil, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(dot).frame(width: 7, height: 7)
                }
                Text(value)
                    .font(monospaced ? .caption.monospaced() : .body)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func ioBlock(_ title: String, _ up: UInt64, _ down: UInt64, _ upIcon: String, _ downIcon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: upIcon).foregroundStyle(.secondary)
                Text(formatInspectBytes(up)).font(.subheadline.monospacedDigit().weight(.semibold))
            }
            HStack(spacing: 4) {
                Image(systemName: downIcon).foregroundStyle(.secondary)
                Text(formatInspectBytes(down)).font(.subheadline.monospacedDigit().weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sparkline(
        title: String,
        points: [DockerStatPoint],
        value: (DockerStatPoint) -> Double,
        current: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(current)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(color)
            }
            DockerSparkline(values: points.map(value), color: color)
                .frame(height: 72)
        }
    }

    private func actionRow(_ title: String, _ icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detailRow(_ title: String, _ icon: String, _ kind: DockerTextKind) -> some View {
        Button {
            textKind = kind
        } label: {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum DockerTextKind: String, Identifiable, Hashable {
    case logs
    case processes
    case inspect
    var id: String { rawValue }

    var title: String {
        switch self {
        case .logs: return "日志"
        case .processes: return "进程"
        case .inspect: return "检查"
        }
    }
}

struct DockerTextPage: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    let containerName: String
    let kind: DockerTextKind
    @State private var text = "加载中…"

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .background(HostpaneTheme.page)
        .navigationTitle(kind.title)
        .task {
            let command: String
            switch kind {
            case .logs: command = DockerProbe.logsCommand(name: containerName)
            case .processes: command = DockerProbe.topCommand(name: containerName)
            case .inspect: command = DockerProbe.inspectCommand(name: containerName)
            }
            text = await model.dockerText(for: host, command: command)
        }
    }
}

private struct DockerSparkline: View {
    var values: [Double]
    var color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }
            let peak = max(values.max() ?? 1, 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let y = size.height - size.height * CGFloat(value / peak)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .color(color.opacity(0.12)))
            context.stroke(path, with: .color(color), lineWidth: 2)
        }
    }
}

func formatDockerCreated(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = iso.date(from: trimmed) ?? {
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: trimmed)
    }()
    guard let date else { return trimmed }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy年M月d日 HH:mm"
    return formatter.string(from: date)
}
