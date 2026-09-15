import SwiftUI
import HostpaneCore

enum InspectDetail: String, Identifiable {
    case processes
    case network
    case storage

    var id: String { rawValue }
}

enum ProcessSortField: String, CaseIterable {
    case pid
    case command
    case user
    case cpu
    case memory
}

struct ProcessSort {
    var field: ProcessSortField = .cpu
    var ascending = false

    mutating func select(_ field: ProcessSortField) {
        if self.field == field {
            ascending.toggle()
        } else {
            self.field = field
            ascending = field == .command || field == .user || field == .pid
        }
    }

    func applied(_ processes: [ProcessSample]) -> [ProcessSample] {
        processes.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch field {
            case .pid:
                comparison = compare(lhs.pid, rhs.pid)
            case .command:
                comparison = lhs.command.localizedCaseInsensitiveCompare(rhs.command)
            case .user:
                comparison = lhs.user.localizedCaseInsensitiveCompare(rhs.user)
            case .cpu:
                comparison = compare(lhs.cpuPercent, rhs.cpuPercent)
            case .memory:
                comparison = compare(lhs.rssBytes, rhs.rssBytes)
            }
            if comparison == .orderedSame {
                return lhs.pid < rhs.pid
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }
}

struct InspectSectionHeader: View {
    var title: String
    var systemImage: String
    var color: Color
    var showsChevron: Bool = false

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(color)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct ProcessTableView: View {
    var processes: [ProcessSample]
    @Binding var sort: ProcessSort
    var limit: Int? = nil

    var body: some View {
        let rows = Array(sort.applied(processes).prefix(limit ?? processes.count))
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                header("Pid", .pid, width: 64, alignment: .leading)
                header("Process", .command, width: nil, alignment: .leading)
                header("User", .user, width: 76, alignment: .trailing)
                header("CPU%", .cpu, width: 56, alignment: .trailing)
                header("Mem", .memory, width: 64, alignment: .trailing)
            }
            .padding(.vertical, 4)
            if rows.isEmpty {
                Text("暂无进程数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                ForEach(rows) { process in
                    HStack(spacing: 8) {
                        Text("\(process.pid)")
                            .frame(width: 64, alignment: .leading)
                        Text(process.command)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(process.user)
                            .lineLimit(1)
                            .frame(width: 76, alignment: .trailing)
                        Text(String(format: "%.1f", process.cpuPercent))
                            .frame(width: 56, alignment: .trailing)
                        Text(formatInspectBytes(process.rssBytes))
                            .frame(width: 64, alignment: .trailing)
                    }
                    .font(.caption.monospacedDigit())
                }
            }
        }
    }

    private func header(_ title: String, _ field: ProcessSortField, width: CGFloat?, alignment: Alignment) -> some View {
        let active = sort.field == field
        return Button {
            sort.select(field)
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if active {
                    Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(active ? HostpaneTheme.offline : .secondary)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct NetworkUsageBlock: View {
    var iface: InterfaceSample
    var hideAddress: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(iface.name, systemImage: "cable.connector")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !hideAddress, let cidr = iface.ipv4CIDR, !cidr.isEmpty {
                    Text(cidr)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Divider()
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    trafficRate(up: true, value: iface.transmitBytesPerSecond)
                    trafficRate(up: false, value: iface.receiveBytesPerSecond)
                }
                Spacer(minLength: 8)
                SplitTrafficDonut(upBytes: iface.transmitBytes, downBytes: iface.receiveBytes)
                VStack(alignment: .trailing, spacing: 10) {
                    trafficTotal(up: true, bytes: iface.transmitBytes)
                    trafficTotal(up: false, bytes: iface.receiveBytes)
                }
            }
        }
    }

    private func trafficRate(up: Bool, value: Double?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(up ? HostpaneTheme.netUp : HostpaneTheme.netDown)
            Text(value.map(formatCompactRate) ?? "—")
                .font(.title3.monospacedDigit().weight(.semibold))
        }
    }

    private func trafficTotal(up: Bool, bytes: UInt64) -> some View {
        HStack(spacing: 8) {
            Image(systemName: up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(up ? HostpaneTheme.netUp : HostpaneTheme.netDown)
            Text(formatInspectBytes(bytes))
                .font(.title3.monospacedDigit().weight(.semibold))
        }
    }
}

struct StorageUsageBlock: View {
    var disk: DiskSample
    var showsIO: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(disk.filesystem)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer()
                Text("\(formatInspectBytes(disk.usedBytes)) / \(formatInspectBytes(disk.totalBytes))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            StorageBar(ratio: disk.usedRatio)
            HStack {
                Text(disk.mount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                if !disk.fstype.isEmpty {
                    Text(disk.fstype)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if showsIO, disk.hasIOStats {
                Divider().padding(.top, 4)
                DiskIOTable(disk: disk)
            }
        }
    }
}

struct DiskIOTable: View {
    var disk: DiskSample

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Color.clear.frame(width: 22)
                columnTitle("速度")
                columnTitle("延迟")
                columnTitle("IOPS")
                columnTitle("总体", alignment: .trailing)
            }
            ioRow(
                letter: "R",
                color: HostpaneTheme.netUp,
                speed: disk.readBytesPerSecond,
                latency: disk.readLatencyMs,
                iops: disk.readIOPS,
                total: disk.readBytes
            )
            ioRow(
                letter: "W",
                color: HostpaneTheme.netDown,
                speed: disk.writeBytesPerSecond,
                latency: disk.writeLatencyMs,
                iops: disk.writeIOPS,
                total: disk.writeBytes
            )
        }
        .font(.caption)
        .padding(.top, 4)
    }

    private func columnTitle(_ title: String, alignment: Alignment = .center) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func ioRow(
        letter: String,
        color: Color,
        speed: Double?,
        latency: Double?,
        iops: Double?,
        total: UInt64
    ) -> some View {
        HStack {
            ZStack {
                Circle().stroke(color, lineWidth: 1.4)
                Text(letter)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)
            }
            .frame(width: 18, height: 18)
            Text(speed.map(formatCompactRate) ?? "—")
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity)
            Text(latency.map(formatMillis) ?? "—")
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity)
            Text(iops.map(formatIOPS) ?? "—")
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity)
            Text(formatInspectBytes(total))
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct ProcessDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var hostID: UUID
    @State private var sort = ProcessSort()
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            Text("进程")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 10)
            Divider()
            ScrollView {
                ProcessTableView(processes: filtered, sort: $sort)
                    .padding(18)
            }
            Divider()
            HStack {
                TextField("PID、进程名或用户", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var processes: [ProcessSample] {
        model.runtime(for: hostID).metrics?.processes ?? []
    }

    private var filtered: [ProcessSample] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return processes }
        return processes.filter { process in
            "\(process.pid)".contains(trimmed)
                || process.command.localizedCaseInsensitiveContains(trimmed)
                || process.user.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

struct NetworkDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var hostID: UUID

    private var interfaces: [InterfaceSample] {
        model.runtime(for: hostID).metrics?.interfaces ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("网络使用情况")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 12) {
                    if interfaces.isEmpty {
                        Text("还没有网络样本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    } else {
                        ForEach(interfaces) { iface in
                            InspectCard {
                                NetworkUsageBlock(
                                    iface: iface,
                                    hideAddress: model.hosts.first(where: { $0.id == hostID })?.hideAddress ?? false
                                )
                            }
                        }
                    }
                }
                .padding(18)
            }
            Divider()
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

struct StorageDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var hostID: UUID

    private var disks: [DiskSample] {
        model.runtime(for: hostID).metrics?.disks ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("存储")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 12) {
                    if disks.isEmpty {
                        Text("还没有磁盘样本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    } else {
                        ForEach(disks) { disk in
                            InspectCard {
                                StorageUsageBlock(disk: disk, showsIO: true)
                            }
                        }
                    }
                }
                .padding(18)
            }
            Divider()
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(minWidth: 560, minHeight: 520)
    }
}
