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
    case dashboard
    case dashboardBackground
    case statusLayout
    case terminalLog
    case appLog

    var title: String {
        switch self {
        case .dashboard: return "仪表板"
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
    @State private var pages: [SettingsPage] = []
    @State private var logChrome = LogPageChrome()

    var body: some View {
        @Bindable var model = model
        page
            .frame(minWidth: 520, minHeight: 560)
            .modifier(HiddenWindowTitle())
            .background {
                SettingsTitlebarLeading(
                    title: pages.last?.title ?? "设置",
                    showsBack: !pages.isEmpty,
                    showsLogTools: pages.last == .appLog,
                    logChrome: logChrome
                ) {
                    if !pages.isEmpty { pages.removeLast() }
                }
            }
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

    @ViewBuilder
    private var page: some View {
        switch pages.last {
        case nil:
            rootForm
        case .dashboard:
            DashboardSettingsView { pages.append($0) }
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

    private var rootForm: some View {
        Form {
            appearanceSection
            syncSection
            connectionSection
            terminalSection
            sftpSection
            loggingSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var appearanceSection: some View {
        @Bindable var model = model
        Section {
            settingsRow("仪表板", systemImage: "gauge.with.needle") {
                pages.append(.dashboard)
            }
            Picker("外观", selection: $model.settings.appearance) {
                ForEach(AppearancePreference.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } header: {
            Text("外观")
        } footer: {
            Text("浅色和深色会覆盖系统外观。终端调色板跟着这里走。")
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        @Bindable var model = model
        Section {
            Picker("同步位置", selection: syncDestinationBinding) {
                ForEach(ConfigSyncDestination.allCases) { destination in
                    Text(destination.title).tag(destination)
                }
            }
            HStack {
                Text("同步状态")
                Spacer()
                Label(syncStatusText, systemImage: ConfigSync.destination.statusSymbol)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            if let notice = model.configSyncNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("数据同步")
        } footer: {
            Text("主机簿、设置和密钥列表会放到 iCloud Drive 或 Dropbox 里由系统同步。密码留在本机钥匙串，不会上传。两台电脑同时改同一份列表时，后保存的会覆盖先保存的；切到已有数据的位置时会先问你保留哪边。")
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
    private var connectionSection: some View {
        @Bindable var model = model
        Section {
            Stepper(value: $model.settings.connectionTimeoutSeconds, in: 5...120) {
                Label(
                    "连接超时：\(model.settings.connectionTimeoutSeconds) 秒",
                    systemImage: "clock"
                )
            }
            Toggle(isOn: $model.settings.alwaysTrustHostKeys) {
                Label("始终信任主机密钥", systemImage: "network")
            }
        } header: {
            Text("连接")
        } footer: {
            Text("启用后，Hostpane 会接受新的或已更改的主机密钥，不再按首次信任固定。只适合你完全控制的环境。")
        }
    }

    @ViewBuilder
    private var terminalSection: some View {
        @Bindable var model = model
        Section {
            Toggle("终端提示音", isOn: $model.settings.terminalBellEnabled)
            Toggle("建议端口转发", isOn: $model.settings.suggestPortForward)
            Toggle("保持会话活跃", isOn: $model.settings.terminalKeepAlive)
            Stepper(value: $model.settings.terminalKeepAliveSeconds, in: 5...120) {
                Text("心跳间隔：\(model.settings.terminalKeepAliveSeconds) 秒")
            }
            .disabled(!model.settings.terminalKeepAlive)
            settingsRow("终端调试日志", systemImage: "doc.text") {
                pages.append(.terminalLog)
            }
        } header: {
            Text("终端")
        } footer: {
            Text("心跳相当于 ssh 的 ServerAliveInterval，用来撑过路由器和云防火墙的空闲超时。电脑休眠、切换网络或服务器重启还是会断。")
        }
    }

    @ViewBuilder
    private var sftpSection: some View {
        @Bindable var model = model
        Section {
            Toggle("保持会话活跃", isOn: $model.settings.sftpKeepAlive)
            Stepper(value: $model.settings.sftpKeepAliveSeconds, in: 5...120) {
                Text("心跳间隔：\(model.settings.sftpKeepAliveSeconds) 秒")
            }
            .disabled(!model.settings.sftpKeepAlive)
            Picker("文本文件打开方式", selection: $model.settings.textFileOpener) {
                ForEach(TextFileOpener.allCases) { opener in
                    Text(opener.title).tag(opener)
                }
            }
            Button("管理快速查看缓存") {
                clearCache()
            }
        } header: {
            Text("SFTP")
        } footer: {
            Text("SFTP 同样会发心跳，避免闲置被中间设备掐掉。双击文本文件时，内置预览或系统默认应用按这里选择。")
        }
    }

    @ViewBuilder
    private var loggingSection: some View {
        @Bindable var model = model
        Section {
            Toggle("记录应用日志", isOn: $model.settings.appLoggingEnabled)
            settingsRow("查看日志", systemImage: "doc.text") {
                pages.append(.appLog)
            }
            Button("在 Finder 中显示") {
                model.logger.revealInFinder()
            }
            Button("用默认应用打开文件") {
                model.logger.openInEditor()
            }
        } header: {
            Text("开发日志")
        } footer: {
            Text("开发期间默认打开。日志写在 ~/Library/Logs/Hostpane/hostpane.log，超过 5 MB 会轮转。密码和密钥内容不会写入。")
        }
    }

    private func settingsRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

private struct HiddenWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

/// Pins the settings title to the left of the title bar, next to the traffic lights.
/// Matches the main window's unified toolbar chrome, measured on this OS.
private let settingsTitlebarHeight: CGFloat = 66
private struct SettingsTitlebarLeading: NSViewRepresentable {
    var title: String
    var showsBack: Bool
    var showsLogTools: Bool
    var logChrome: LogPageChrome
    var back: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.title = title
        context.coordinator.showsBack = showsBack
        context.coordinator.showsLogTools = showsLogTools
        context.coordinator.logChrome = logChrome
        context.coordinator.back = back
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            coordinator.install(from: nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var title = ""
        var showsBack = false
        var showsLogTools = false
        var logChrome: LogPageChrome?
        var back: () -> Void = {}
        private weak var window: NSWindow?
        private var accessory: NSTitlebarAccessoryViewController?
        private var hostWidth: NSLayoutConstraint?
        private var hostHeight: NSLayoutConstraint?

        private let backButton = NSButton()
        private let label = NSTextField(labelWithString: "")
        private let toolWell = NSView()
        private let toolStack = NSStackView()
        private let refreshButton = NSButton()
        private let copyButton = NSButton()
        private let trashButton = NSButton()
        private let searchField = NSSearchField()
        private let stack = NSStackView()

        override init() {
            super.init()
            backButton.bezelStyle = .circular
            backButton.controlSize = .large
            backButton.image = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "返回")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
            backButton.imageScaling = .scaleProportionallyDown
            backButton.target = self
            backButton.action = #selector(goBack)
            backButton.toolTip = "返回"
            backButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                backButton.widthAnchor.constraint(equalToConstant: 32),
                backButton.heightAnchor.constraint(equalToConstant: 32)
            ])
            label.font = .systemFont(ofSize: 17, weight: .semibold)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.setContentHuggingPriority(.required, for: .horizontal)
            configureTool(refreshButton, symbol: "arrow.clockwise", tip: "刷新", action: #selector(reloadLog))
            configureTool(copyButton, symbol: "doc.on.doc", tip: "复制", action: #selector(copyLog))
            configureTool(trashButton, symbol: "trash", tip: "清除", action: #selector(clearLog))
            toolStack.orientation = .horizontal
            toolStack.alignment = .centerY
            toolStack.spacing = 2
            toolStack.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
            toolWell.wantsLayer = true
            toolWell.layer?.cornerRadius = 18
            toolStack.translatesAutoresizingMaskIntoConstraints = false
            toolWell.addSubview(toolStack)
            NSLayoutConstraint.activate([
                toolStack.leadingAnchor.constraint(equalTo: toolWell.leadingAnchor),
                toolStack.trailingAnchor.constraint(equalTo: toolWell.trailingAnchor),
                toolStack.topAnchor.constraint(equalTo: toolWell.topAnchor),
                toolStack.bottomAnchor.constraint(equalTo: toolWell.bottomAnchor),
                toolWell.heightAnchor.constraint(equalToConstant: 36)
            ])
            searchField.placeholderString = "搜索日志"
            searchField.delegate = self
            searchField.target = self
            searchField.action = #selector(searchChanged)
            searchField.sendsSearchStringImmediately = true
            searchField.translatesAutoresizingMaskIntoConstraints = false
            searchField.widthAnchor.constraint(equalToConstant: 220).isActive = true
            searchField.controlSize = .large
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 10
        }

        private func configureTool(_ button: NSButton, symbol: String, tip: String, action: Selector) {
            button.isBordered = false
            button.bezelStyle = .shadowlessSquare
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.toolTip = tip
            button.target = self
            button.action = action
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 32),
                button.heightAnchor.constraint(equalToConstant: 30)
            ])
        }

        func install(from anchor: NSView) {
            guard let window = anchor.window else { return }
            if self.window !== window || accessory == nil {
                remove()
                if window.toolbar == nil {
                    let toolbar = NSToolbar(identifier: "hostpane.settings")
                    toolbar.displayMode = .iconOnly
                    window.toolbar = toolbar
                }
                window.toolbarStyle = .unified
                window.layoutIfNeeded()
                let chrome = titlebarHeight(of: window)
                let host = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: chrome))
                host.setContentHuggingPriority(.required, for: .horizontal)
                stack.translatesAutoresizingMaskIntoConstraints = false
                stack.setHuggingPriority(.required, for: .horizontal)
                host.addSubview(stack)
                let width = host.widthAnchor.constraint(equalToConstant: 240)
                let height = host.heightAnchor.constraint(equalToConstant: chrome)
                hostWidth = width
                hostHeight = height
                NSLayoutConstraint.activate([
                    height,
                    width,
                    stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 6),
                    stack.centerYAnchor.constraint(equalTo: host.centerYAnchor)
                ])
                let controller = NSTitlebarAccessoryViewController()
                controller.layoutAttribute = .left
                controller.view = host
                window.addTitlebarAccessoryViewController(controller)
                accessory = controller
                self.window = window
            }
            apply()
        }

        private func tintToolButtons() {
            let appearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
            appearance.performAsCurrentDrawingAppearance {
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let tint: NSColor = dark ? .white : .labelColor
                let symbol = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
                let names = ["arrow.clockwise", "doc.on.doc", "trash"]
                for (button, name) in zip([refreshButton, copyButton, trashButton], names) {
                    button.image = NSImage(systemSymbolName: name, accessibilityDescription: button.toolTip)?
                        .withSymbolConfiguration(symbol)
                    button.contentTintColor = tint
                }
                let fill = dark
                    ? NSColor.white.withAlphaComponent(0.14)
                    : NSColor.black.withAlphaComponent(0.06)
                toolWell.layer?.backgroundColor = fill.cgColor
                toolWell.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(dark ? 0.35 : 0.4).cgColor
            }
        }

        private func titlebarHeight(of window: NSWindow) -> CGFloat {
            let chrome = window.frame.height - window.contentLayoutRect.maxY
            if chrome >= 44 { return chrome }
            return settingsTitlebarHeight
        }

        func remove() {
            guard let window, let accessory else { return }
            if let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory }) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            self.accessory = nil
            self.window = nil
        }

        private func apply() {
            label.stringValue = title
            backButton.isHidden = !showsBack
            copyButton.isEnabled = logChrome?.canCopy ?? false
            trashButton.isEnabled = logChrome?.canClear ?? false
            if searchField.stringValue != logChrome?.query {
                searchField.stringValue = logChrome?.query ?? ""
            }
            let tools = [refreshButton, copyButton, trashButton]
            let toolMatches = toolStack.arrangedSubviews.count == tools.count
                && zip(toolStack.arrangedSubviews, tools).allSatisfy { $0 === $1 }
            if !toolMatches {
                toolStack.arrangedSubviews.forEach {
                    toolStack.removeArrangedSubview($0)
                    $0.removeFromSuperview()
                }
                tools.forEach { toolStack.addArrangedSubview($0) }
            }
            var views: [NSView] = showsBack ? [backButton, label] : [label]
            if showsLogTools {
                views.append(contentsOf: [toolWell, searchField])
            }
            let current = stack.arrangedSubviews
            let matches = current.count == views.count && zip(current, views).allSatisfy { $0 === $1 }
            if !matches {
                current.forEach {
                    stack.removeArrangedSubview($0)
                    $0.removeFromSuperview()
                }
                views.forEach { stack.addArrangedSubview($0) }
            }
            tintToolButtons()
            if stack.arrangedSubviews.contains(where: { $0 === label }) {
                stack.setCustomSpacing(22, after: label)
            }
            if stack.arrangedSubviews.contains(where: { $0 === toolWell }) {
                stack.setCustomSpacing(10, after: toolWell)
            }
            let fitted = ceil(stack.fittingSize.width + 12)
            hostWidth?.constant = max(180, fitted)
            if let window {
                let chrome = titlebarHeight(of: window)
                hostHeight?.constant = chrome
            }
            if var frame = accessory?.view.frame {
                frame.size.width = hostWidth?.constant ?? fitted
                frame.size.height = hostHeight?.constant ?? settingsTitlebarHeight
                accessory?.view.frame = frame
            }
        }

        @objc private func goBack() {
            back()
        }

        @objc private func reloadLog() {
            logChrome?.performReload()
        }

        @objc private func copyLog() {
            logChrome?.performCopy()
        }

        @objc private func clearLog() {
            logChrome?.requestClear()
        }

        @objc private func searchChanged() {
            logChrome?.query = searchField.stringValue
        }

        func controlTextDidChange(_ notification: Notification) {
            guard notification.object as? NSSearchField === searchField else { return }
            logChrome?.query = searchField.stringValue
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


