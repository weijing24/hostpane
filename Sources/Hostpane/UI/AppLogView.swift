import AppKit
import SwiftUI
import HostpaneCore

struct AppLogView: View {
    @Environment(AppModel.self) private var model
    var chrome: LogPageChrome
    @State private var category = "全部"
    @State private var level = "全部"
    @State private var machine = "全部机器"

    var body: some View {
        @Bindable var chrome = chrome
        let rows = filtered
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                countRows
                filterSection
                recentSection(rows)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(HostpaneTheme.page)
        .background {
            Color.clear.task(id: rows.map(\.id)) {
                chrome.setVisible(rows, total: combined.count)
            }
        }
        .alert("清除日志?", isPresented: $chrome.confirmClear) {
            Button("取消", role: .cancel) {}
            Button("清除日志", role: .destructive) {
                chrome.performClear()
            }
        } message: {
            Text("这会移除此设备上存储的最近日志。")
        }
        .onAppear {
            chrome.attach(model.logger)
            chrome.performReload()
        }
        .onChange(of: model.logger.lines.count) { _, _ in
            chrome.setVisible(filtered, total: combined.count)
        }
    }

    private var countRows: some View {
        VStack(spacing: 0) {
            stat("list.bullet.rectangle", "总计", combined.count)
            stat("exclamationmark.triangle", "错误", combined.filter { $0.level == .error }.count)
            stat("exclamationmark.circle", "警告", combined.filter { $0.level == .warn }.count)
        }
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("筛选")
                .font(.headline)
            filterRow("类别", selection: $category, options: LogFilterCatalog.categories)
            Divider()
            filterRow("级别", selection: $level, options: LogFilterCatalog.levels)
            Divider()
            filterRow("机器", selection: $machine, options: machineOptions)
        }
    }

    private func recentSection(_ rows: [AppLogLine]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近")
                .font(.headline)
            if rows.isEmpty {
                Text("没有符合当前筛选条件的日志。")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                ForEach(rows) { line in
                    logRow(line)
                    Divider()
                }
            }
        }
    }

    private func stat(_ symbol: String, _ title: String, _ value: Int) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value, format: .number)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func filterRow(_ title: String, selection: Binding<String>, options: [LogFilterOption]) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 16)
            Picker(title, selection: selection) {
                ForEach(options) { option in
                    if let symbol = option.symbol {
                        Label(option.title, systemImage: symbol).tag(option.title)
                    } else {
                        Text(option.title).tag(option.title)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 6)
    }

    private func logRow(_ line: AppLogLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(line.level.tint)
                    .frame(width: 8, height: 8)
                Text(line.categoryTitle)
                    .foregroundStyle(line.level.tint)
                Text(line.level.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(line.level.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(line.level.tint)
                Spacer(minLength: 8)
                Text(line.clockTime)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(line.message)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private var combined: [AppLogLine] {
        var seen = Set<String>()
        var rows: [AppLogLine] = []
        for line in (chrome.fileLines + model.logger.lines).reversed() {
            let key = line.formattedLine
            if seen.insert(key).inserted {
                rows.append(line)
            }
        }
        return rows
    }

    private var filtered: [AppLogLine] {
        let needle = chrome.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.filter { line in
            if category != "全部", line.categoryTitle != category { return false }
            if level != "全部", line.level.title != level { return false }
            if machine != "全部机器", !line.mentions(machine, hosts: model.hosts) { return false }
            if !needle.isEmpty {
                let haystack = "\(line.category) \(line.level.title) \(line.message)"
                if !haystack.localizedStandardContains(needle) { return false }
            }
            return true
        }
    }

    private var machineOptions: [LogFilterOption] {
        [LogFilterOption(title: "全部机器")] + model.hosts.map { LogFilterOption(title: $0.displayName) }
    }

}

extension AppLogLevel {
    var title: String {
        switch self {
        case .debug: return "调试"
        case .info: return "信息"
        case .warn: return "警告"
        case .error: return "错误"
        }
    }

    var tint: Color {
        switch self {
        case .debug: return .secondary
        case .info: return Color(red: 0.20, green: 0.62, blue: 0.98)
        case .warn: return Color(red: 0.95, green: 0.62, blue: 0.15)
        case .error: return Color(red: 0.94, green: 0.30, blue: 0.32)
        }
    }
}

struct LogFilterOption: Identifiable, Hashable {
    var title: String
    var symbol: String?
    var id: String { title }
}

enum LogFilterCatalog {
    static let categories: [LogFilterOption] = [
        LogFilterOption(title: "全部", symbol: "circle"),
        LogFilterOption(title: "仪表板", symbol: "gauge.with.needle"),
        LogFilterOption(title: "机器状态", symbol: "list.bullet.rectangle"),
        LogFilterOption(title: "终端", symbol: "apple.terminal"),
        LogFilterOption(title: "SFTP", symbol: "folder"),
        LogFilterOption(title: "端口转发", symbol: "arrow.triangle.branch"),
        LogFilterOption(title: "小组件", symbol: "square.grid.2x2"),
        LogFilterOption(title: "Docker", symbol: "shippingbox"),
        LogFilterOption(title: "订阅", symbol: "creditcard")
    ]

    static let levels: [LogFilterOption] = [
        LogFilterOption(title: "全部"),
        LogFilterOption(title: AppLogLevel.error.title),
        LogFilterOption(title: AppLogLevel.warn.title),
        LogFilterOption(title: AppLogLevel.info.title),
        LogFilterOption(title: AppLogLevel.debug.title)
    ]
}

extension AppLogLine {
    var categoryTitle: String {
        switch category.lowercased() {
        case "docker": return "Docker"
        case "app", "dashboard": return "仪表板"
        case "metrics", "status", "monitor", "probe": return "机器状态"
        case "ssh", "terminal": return "终端"
        case "sftp": return "SFTP"
        case "forward", "portforward", "port": return "端口转发"
        case "widget": return "小组件"
        case "subscription", "license": return "订阅"
        default: return category
        }
    }

    var clockTime: String {
        Self.clock.string(from: timestamp)
    }

    func mentions(_ name: String, hosts: [HostRecord]) -> Bool {
        let host = hosts.first { $0.displayName == name }
        let needles = [name, host?.hostname].compactMap { $0?.lowercased() }.filter { !$0.isEmpty }
        let text = message.lowercased()
        return needles.contains { text.contains($0) }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
