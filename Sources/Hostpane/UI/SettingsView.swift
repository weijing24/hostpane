import AppKit
import SwiftUI
import HostpaneCore

@MainActor
@Observable
final class LogPageChrome {
    var query = ""
    var fileLines: [AppLogLine] = []
    var confirmClear = false
    var canCopy = false
    var canClear = false
    private var logger: AppLogger?
    private var visibleText = ""

    func attach(_ logger: AppLogger) {
        self.logger = logger
    }

    func performReload() {
        fileLines = logger?.recentFileLines() ?? []
    }

    func requestClear() {
        guard canClear else { return }
        confirmClear = true
    }

    func performClear() {
        logger?.clear()
        fileLines = []
        query = ""
        visibleText = ""
        canCopy = false
        canClear = false
    }

    func setVisible(_ lines: [AppLogLine], total: Int) {
        visibleText = lines.map(\.formattedLine).joined(separator: "\n")
        canCopy = !lines.isEmpty
        canClear = total > 0
    }

    func performCopy() {
        guard canCopy, !visibleText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(visibleText, forType: .string)
    }
}

enum SettingsPage: Hashable {
    case dashboardBackground
    case statusLayout
    case terminalLog
    case appLog

    var title: String {
        switch self {
        case .dashboardBackground: return "仪表板背景"
        case .statusLayout: return "状态详情布局"
        case .terminalLog: return "终端调试日志"
        case .appLog: return "日志"
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var cacheMessage: String?
    @State private var tab: SettingsTab = .dashboard
    @State private var pages: [SettingsPage] = []
    @State private var query = ""
    @State private var hoveredTab: SettingsTab?
    @State private var logChrome = LogPageChrome()

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 880, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .modifier(HiddenWindowTitle())
        .onChange(of: model.settings) { _, _ in
            model.persistSettings()
        }
        .alert("快速查看缓存", isPresented: Binding(
            get: { cacheMessage != nil },
            set: { if !$0 { cacheMessage = nil } }
        )) {
            Button("好", role: .cancel) { cacheMessage = nil }
        } message: {
            Text(cacheMessage ?? "")
        }
    }

    private var sidebar: some View {
        let sections = SettingsTabSection.allCases.compactMap { section -> (SettingsTabSection, [SettingsTab])? in
            let tabs = SettingsTab.allCases.filter { $0.section == section && $0.matches(query) }
            return tabs.isEmpty ? nil : (section, tabs)
        }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .hostpaneGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous), interactive: true)
            ScrollView {
                if sections.isEmpty {
                    Text("没有匹配的设置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(sections, id: \.0.id) { pair in
                            let section = pair.0
                            let tabs = pair.1
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 4)
                                ForEach(tabs) { item in
                                    sidebarRow(item)
                                }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(width: SettingsChrome.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sidebarRow(_ item: SettingsTab) -> some View {
        let selected = tab == item
        return Button {
            tab = item
            pages.removeAll()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(item.tint)
                    .frame(width: 22)
                Text(item.title)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .modifier(SettingsSidebarGlass(active: selected || hoveredTab == item, tinted: selected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredTab = hovering ? item : (hoveredTab == item ? nil : hoveredTab)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeader
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 12)
            detailBody
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var detailTitle: String {
        pages.last?.title ?? tab.title
    }

    private var detailHeader: some View {
        HStack(spacing: 10) {
            if !pages.isEmpty {
                Button {
                    pages.removeLast()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("返回")
            }
            Text(detailTitle)
                .font(.system(size: 22, weight: .bold))
            Spacer(minLength: 12)
            if pages.last == .appLog {
                logTools
            }
        }
    }

    private var logTools: some View {
        @Bindable var chrome = logChrome
        return HStack(spacing: 8) {
            HStack(spacing: 2) {
                logTool("arrow.clockwise", help: "刷新", enabled: true) { chrome.performReload() }
                logTool("doc.on.doc", help: "复制", enabled: chrome.canCopy) { chrome.performCopy() }
                logTool("trash", help: "清除", enabled: chrome.canClear) { chrome.requestClear() }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            TextField("搜索日志", text: $chrome.query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
    }

    private func logTool(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 28, height: 26)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(help)
    }

    @ViewBuilder
    private var detailBody: some View {
        switch pages.last {
        case nil:
            ScrollView {
                tabBody
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .dashboardBackground:
            DashboardBackgroundSettingsView()
        case .statusLayout:
            StatusLayoutEditorView()
        case .terminalLog:
            TerminalDebugLogView()
        case .appLog:
            AppLogView(chrome: logChrome)
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        switch tab {
        case .general:
            generalPane
        case .security:
            securityPane
        case .sync:
            syncPane
        case .connection:
            connectionPane
        case .dashboard:
            DashboardSettingsView { pages.append($0) }
        case .terminal:
            terminalPane
        case .sftp:
            sftpPane
        case .diagnostics:
            diagnosticsPane
        }
    }

    @ViewBuilder
    private var generalPane: some View {
        @Bindable var model = model
        SettingsGroup(
            title: "外观",
            footer: "浅色和深色会覆盖系统外观。终端调色板跟着这里走。"
        ) {
            SettingsLabeledRow(title: "外观") {
                Picker("外观", selection: $model.settings.appearance) {
                    ForEach(AppearancePreference.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var securityPane: some View {
        @Bindable var model = model
        SettingsGroup(
            title: "主机密钥",
            footer: "启用后，Hostpane 会接受新的或已更改的主机密钥，不再按首次信任固定。只适合你完全控制的环境。"
        ) {
            SettingsToggleRow(title: "始终信任主机密钥", isOn: $model.settings.alwaysTrustHostKeys)
        }
    }

    @ViewBuilder
    private var syncPane: some View {
        @Bindable var model = model
        SettingsGroup(
            title: "数据同步",
            footer: "主机簿、设置和密钥列表会放到 iCloud Drive 或 Dropbox 里由系统同步。密码留在本机钥匙串，不会上传。两台电脑同时改同一份列表时，后保存的会覆盖先保存的；切到已有数据的位置时会先问你保留哪边。"
        ) {
            SettingsLabeledRow(title: "同步位置") {
                Picker("同步位置", selection: syncDestinationBinding) {
                    ForEach(ConfigSyncDestination.allCases) { destination in
                        Text(destination.title).tag(destination)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsHairline()
            SettingsLabeledRow(title: "同步状态") {
                Label(syncStatusText, systemImage: ConfigSync.destination.statusSymbol)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            if let notice = model.configSyncNotice {
                SettingsHairline()
                Text(notice)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert(
            "无法切换同步位置",
            isPresented: Binding(
                get: { model.configSyncError != nil },
                set: { if !$0 { model.configSyncError = nil } }
            )
        ) {
            Button("好", role: .cancel) { model.configSyncError = nil }
        } message: {
            Text(model.configSyncError ?? "")
        }
        .confirmationDialog(
            "两边的数据不一样",
            isPresented: Binding(
                get: { model.configSyncPending != nil },
                set: { if !$0 { model.cancelConfigSync() } }
            ),
            titleVisibility: .visible
        ) {
            if joiningCloud {
                Button(keepDestinationTitle) {
                    model.confirmConfigSync(.keepDestination)
                }
                Button(keepSourceTitle, role: .destructive) {
                    model.confirmConfigSync(.keepSource)
                }
            } else {
                Button(keepSourceTitle) {
                    model.confirmConfigSync(.keepSource)
                }
                Button(keepDestinationTitle) {
                    model.confirmConfigSync(.keepDestination)
                }
            }
            Button("取消", role: .cancel) {
                model.cancelConfigSync()
            }
        } message: {
            Text(conflictMessage)
        }
    }

    private var syncDestinationBinding: Binding<ConfigSyncDestination> {
        Binding(
            get: { ConfigSync.destination },
            set: { model.setConfigSyncDestination($0) }
        )
    }

    private var syncStatusText: String {
        ConfigSync.statusText(for: ConfigSync.destination)
    }

    private var joiningCloud: Bool {
        guard let pending = model.configSyncPending else { return false }
        return pending.destination != .local
    }

    private var keepDestinationTitle: String {
        let title = model.configSyncPending?.destination.title ?? "目标"
        return "使用\(title)已有的数据"
    }

    private var keepSourceTitle: String {
        let title = model.configSyncPending?.destination.title ?? "目标"
        if joiningCloud {
            return "用当前数据覆盖\(title)"
        }
        return "把当前数据复制到\(title)"
    }

    private var conflictMessage: String {
        guard let pending = model.configSyncPending else { return "" }
        let current = ConfigSync.destination.title
        let next = pending.destination.title
        return "当前（\(current)）：\(pending.source.summaryLabel())。\(next)：\(pending.target.summaryLabel())。加入云端时建议保留那边已有的数据。"
    }

    @ViewBuilder
    private var connectionPane: some View {
        @Bindable var model = model
        SettingsGroup(
            title: "超时",
            footer: "建立 SSH 连接时，超过这段时间还没连上就停止。"
        ) {
            SettingsLabeledRow(title: "连接超时") {
                Stepper(value: $model.settings.connectionTimeoutSeconds, in: 5...120) {
                    Text("\(model.settings.connectionTimeoutSeconds) 秒")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var terminalPane: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 26) {
            SettingsGroup(title: "会话") {
                SettingsToggleRow(title: "终端提示音", isOn: $model.settings.terminalBellEnabled)
                SettingsHairline()
                SettingsToggleRow(title: "建议端口转发", isOn: $model.settings.suggestPortForward)
            }
            SettingsGroup(
                title: "心跳",
                footer: "心跳相当于 ssh 的 ServerAliveInterval，用来撑过路由器和云防火墙的空闲超时。电脑休眠、切换网络或服务器重启还是会断。"
            ) {
                SettingsToggleRow(title: "保持会话活跃", isOn: $model.settings.terminalKeepAlive)
                SettingsHairline()
                SettingsLabeledRow(title: "心跳间隔") {
                    Stepper(value: $model.settings.terminalKeepAliveSeconds, in: 5...120) {
                        Text("\(model.settings.terminalKeepAliveSeconds) 秒")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .fixedSize()
                }
                .disabled(!model.settings.terminalKeepAlive)
            }
            SettingsGroup(title: "调试") {
                SettingsChevronRow(title: "终端调试日志") {
                    pages.append(.terminalLog)
                }
            }
        }
    }

    @ViewBuilder
    private var sftpPane: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 26) {
            SettingsGroup(
                title: "会话",
                footer: "SFTP 同样会发心跳，避免闲置被中间设备掐掉。"
            ) {
                SettingsToggleRow(title: "保持会话活跃", isOn: $model.settings.sftpKeepAlive)
                SettingsHairline()
                SettingsLabeledRow(title: "心跳间隔") {
                    Stepper(value: $model.settings.sftpKeepAliveSeconds, in: 5...120) {
                        Text("\(model.settings.sftpKeepAliveSeconds) 秒")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .fixedSize()
                }
                .disabled(!model.settings.sftpKeepAlive)
            }
            SettingsGroup(
                title: "文件",
                footer: "双击文本文件时，内置预览或系统默认应用按这里选择。"
            ) {
                SettingsLabeledRow(title: "文本文件打开方式") {
                    Picker("文本文件打开方式", selection: $model.settings.textFileOpener) {
                        ForEach(TextFileOpener.allCases) { opener in
                            Text(opener.title).tag(opener)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsHairline()
                SettingsActionRow(title: "管理快速查看缓存") {
                    clearCache()
                }
            }
        }
    }

    @ViewBuilder
    private var diagnosticsPane: some View {
        @Bindable var model = model
        SettingsGroup(
            title: "应用日志",
            footer: "开发期间默认打开。日志写在 ~/Library/Logs/Hostpane/hostpane.log，超过 5 MB 会轮转。密码和密钥内容不会写入。"
        ) {
            SettingsToggleRow(title: "记录应用日志", isOn: $model.settings.appLoggingEnabled)
            SettingsHairline()
            SettingsChevronRow(title: "查看日志") {
                pages.append(.appLog)
            }
            SettingsHairline()
            SettingsActionRow(title: "在 Finder 中显示") {
                model.logger.revealInFinder()
            }
            SettingsHairline()
            SettingsActionRow(title: "用默认应用打开文件") {
                model.logger.openInEditor()
            }
        }
    }

    private func clearCache() {
        do {
            let count = try SettingsStore.clearPreviewCache()
            cacheMessage = count == 0 ? "缓存是空的。" : "已删除 \(count) 项缓存。"
        } catch {
            cacheMessage = error.localizedDescription
        }
    }
}

private struct SettingsSidebarGlass: ViewModifier {
    var active: Bool
    var tinted: Bool

    func body(content: Content) -> some View {
        if active {
            content.hostpaneGlass(
                in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                interactive: true,
                tint: tinted ? HostpaneTheme.accent : nil
            )
        } else {
            content
        }
    }
}

private struct HiddenWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}


struct TerminalDebugLogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.sshDebugLogs.isEmpty {
                ContentUnavailableView {
                    Label("还没有日志", systemImage: "doc.text")
                } description: {
                    Text("连接一台机器后，SSH 日志会出现在这里。")
                }
            } else {
                List(model.sshDebugLogs) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.formattedLine)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("清除") { model.clearSSHDebugLogs() }
                    .disabled(model.sshDebugLogs.isEmpty)
            }
            .padding(12)
        }
    }
}


