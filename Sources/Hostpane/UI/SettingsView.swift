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
            if model.configSyncNeedsRestart {
                Text("已复制到新位置，请重新启动 Hostpane。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("数据同步")
        } footer: {
            Text("主机簿、设置和密钥列表会放到 iCloud Drive 或 Dropbox 里由系统同步。密码留在本机钥匙串，不会上传。更改位置后需要重新启动应用才会生效。")
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
    }

    private var syncDestinationBinding: Binding<ConfigSyncDestination> {
        Binding(
            get: { ConfigSync.destination },
            set: { model.setConfigSyncDestination($0) }
        )
    }

    private var syncStatusText: String {
        if model.configSyncNeedsRestart {
            return "等待重新启动"
        }
        return ConfigSync.statusText(for: ConfigSync.destination)
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
