import SwiftUI
import HostpaneCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var cacheMessage: String?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                appearanceSection
                syncSection
                connectionSection
                terminalSection
                sftpSection
                loggingSection
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
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
        .frame(minWidth: 520, minHeight: 560)
    }

    @ViewBuilder
    private var appearanceSection: some View {
        @Bindable var model = model
        Section {
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
            NavigationLink {
                TerminalDebugLogView()
            } label: {
                Text("终端调试日志")
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
            NavigationLink {
                AppLogView()
            } label: {
                Text("查看日志")
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

    private func clearCache() {
        do {
            let count = try SettingsStore.clearPreviewCache()
            cacheMessage = count == 0 ? "缓存是空的。" : "已删除 \(count) 项缓存。"
        } catch {
            cacheMessage = error.localizedDescription
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
        .navigationTitle("终端调试日志")
        .toolbar {
            ToolbarItem {
                Button("清除") { model.clearSSHDebugLogs() }
                    .disabled(model.sshDebugLogs.isEmpty)
            }
        }
    }
}

struct AppLogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.logger.lines.isEmpty {
                ContentUnavailableView {
                    Label("还没有日志", systemImage: "doc.text")
                } description: {
                    Text("打开 Docker、终端或 SFTP 之后，记录会出现在这里。")
                }
            } else {
                List(model.logger.lines.reversed()) { line in
                    Text(line.formattedLine)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(line.level == .error ? Color.red : Color.primary)
                }
            }
        }
        .navigationTitle("应用日志")
        .toolbar {
            ToolbarItem {
                Button("打开文件") { model.logger.openInEditor() }
            }
            ToolbarItem {
                Button("清除") { model.logger.clear() }
                    .disabled(model.logger.lines.isEmpty)
            }
        }
    }
}
