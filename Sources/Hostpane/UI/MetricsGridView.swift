import SwiftUI
import HostpaneCore

struct MetricsGridView: View {
    var metrics: HostMetrics?
    var phase: ConnectionPhase

    var body: some View {
        if let metrics {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(metrics.operatingSystem)
                    if let load = metrics.loadAverage {
                        Text(String(format: "load %.2f %.2f %.2f", load.0, load.1, load.2))
                    }
                    Text("up \(formatUptime(metrics.uptimeSeconds))")
                    Spacer()
                    Text(metrics.hostname)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricCard(
                        title: "CPU",
                        value: metrics.cpuUsage.map { formatPercent($0) } ?? "—",
                        detail: "Share of non-idle time since last sample",
                        ratio: metrics.cpuUsage
                    )
                    MetricCard(
                        title: "Memory",
                        value: "\(formatBytes(metrics.memoryUsedBytes)) / \(formatBytes(metrics.memoryTotalBytes))",
                        detail: "Available \(formatBytes(metrics.memoryAvailableBytes))",
                        ratio: metrics.memoryUsedRatio
                    )
                    MetricCard(
                        title: "Disk",
                        value: diskValue(metrics),
                        detail: diskDetail(metrics),
                        ratio: metrics.disks.first(where: { $0.mount == "/" })?.usedRatio
                            ?? metrics.disks.first?.usedRatio
                    )
                    MetricCard(
                        title: "Network",
                        value: networkValue(metrics),
                        detail: "Sum of non-virtual interfaces, bytes per second",
                        ratio: nil
                    )
                }
            }
        } else if phase == .connected || phase == .connecting {
            ProgressView("Waiting for first sample")
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private func diskValue(_ metrics: HostMetrics) -> String {
        let total = metrics.localStorageBytes
        guard total > 0 else { return "—" }
        return "\(formatBytes(metrics.localStorageUsedBytes)) / \(formatBytes(total))"
    }

    private func diskDetail(_ metrics: HostMetrics) -> String {
        guard let disk = metrics.primaryDisk else {
            return "No df data"
        }
        return "\(disk.mount) on \(disk.filesystem)"
    }

    private func networkValue(_ metrics: HostMetrics) -> String {
        guard let rx = metrics.netReceiveBytesPerSecond, let tx = metrics.netTransmitBytesPerSecond else {
            return "—"
        }
        return "↓ \(formatBytesPerSecond(rx))  ↑ \(formatBytesPerSecond(tx))"
    }
}

private struct MetricCard: View {
    var title: String
    var value: String
    var detail: String
    var ratio: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let ratio {
                ProgressView(value: min(max(ratio, 0), 1))
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

func formatPercent(_ value: Double) -> String {
    String(format: "%.0f%%", value * 100)
}

func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unit = 0
    while value >= 1024 && unit < units.count - 1 {
        value /= 1024
        unit += 1
    }
    if unit == 0 {
        return "\(bytes) B"
    }
    return String(format: "%.1f %@", value, units[unit])
}

func formatBytesPerSecond(_ bytes: Double) -> String {
    formatBytes(UInt64(max(bytes, 0))) + "/s"
}

func formatUptime(_ seconds: Int) -> String {
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 { return "\(days) 天 \(hours) 小时" }
    if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
    return "\(minutes) 分"
}

func formatLatency(_ seconds: Double) -> String {
    let ms = seconds * 1_000
    if ms < 1 { return "<1 ms" }
    if ms < 10 { return String(format: "%.1f ms", ms) }
    return "\(Int(ms.rounded())) ms"
}

func formatCompactRate(_ bytesPerSecond: Double) -> String {
    formatInspectBytes(UInt64(max(bytesPerSecond, 0).rounded())) + "/s"
}

func formatInspectBytes(_ bytes: UInt64) -> String {
    let units = ["B", "K", "M", "G", "T"]
    var value = Double(bytes)
    var unit = 0
    while value >= 1024 && unit < units.count - 1 {
        value /= 1024
        unit += 1
    }
    if unit == 0 {
        return "\(bytes) B"
    }
    if value >= 100 {
        return String(format: "%.0f %@", value, units[unit])
    }
    if value >= 10 {
        return String(format: "%.1f %@", value, units[unit])
    }
    return String(format: "%.2f %@", value, units[unit])
}

func formatIOPS(_ value: Double) -> String {
    if value < 0.5 { return "0" }
    if value < 10 { return String(format: "%.1f", value) }
    return String(format: "%.0f", value)
}

func formatMillis(_ value: Double) -> String {
    if value < 0.5 { return "0 ms" }
    if value < 10 { return String(format: "%.1f ms", value) }
    return String(format: "%.0f ms", value)
}
