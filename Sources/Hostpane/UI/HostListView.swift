import SwiftUI
import HostpaneCore

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            Label("仪表板", systemImage: "gauge.with.needle")
                .tag(SidebarItem.dashboard)

            Section("资源") {
                Label("机器", systemImage: "server.rack")
                    .tag(SidebarItem.machines)
                Label("SSH 密钥", systemImage: "key")
                    .tag(SidebarItem.sshKeys)
            }

            Section("工具箱") {
                Label("代码片段", systemImage: "curlybraces")
                    .tag(SidebarItem.snippets)
                Label {
                    Text("Docker")
                } icon: {
                    DockerWhaleIcon(size: 15)
                }
                .tag(SidebarItem.dockerHome)
            }

            Section("终端") {
                if model.activeSessions.isEmpty {
                    Label("无会话", systemImage: "rectangle.dashed")
                        .foregroundStyle(.secondary)
                        .tag(SidebarItem.terminalHome)
                } else {
                    ForEach(model.activeSessions) { host in
                        sessionLabel(host)
                            .tag(SidebarItem.session(host.id))
                            .contextMenu {
                                Button("断开") { model.disconnect(host) }
                            }
                    }
                }
            }

            Section("SFTP") {
                if model.activeSFTPSessions.isEmpty {
                    Label("无会话", systemImage: "folder")
                        .foregroundStyle(.secondary)
                        .tag(SidebarItem.sftpHome)
                } else {
                    ForEach(model.activeSFTPSessions) { host in
                        sftpLabel(host)
                            .tag(SidebarItem.sftp(host.id))
                            .contextMenu {
                                Button("断开") { model.closeSFTP(host) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .tint(HostpaneTheme.accent)
        .scrollContentBackground(.hidden)
        .transaction { $0.animation = nil }
        .toolbar {
            ToolbarItem {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("设置")
            }
            if case .session(let id) = model.sidebarSelection,
               let host = model.hosts.first(where: { $0.id == id }),
               !model.detachedSessionIDs.contains(id) {
                SessionToolbarItems(host: host)
            }
        }
    }

    private func sessionLabel(_ host: HostRecord) -> some View {
        let runtime = model.runtime(for: host.id)
        return Label {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(host.displayName)
                    Text(sessionSubtitle(runtime.phase))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                sessionCloseButton(help: "关闭终端") {
                    model.disconnect(host)
                }
            }
        } icon: {
            Image(systemName: "terminal.fill")
        }
    }

    private func sftpLabel(_ host: HostRecord) -> some View {
        let runtime = model.runtime(for: host.id)
        return Label {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(host.displayName)
                    Text(sftpSubtitle(runtime.sftpPhase))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                sessionCloseButton(help: "关闭 SFTP") {
                    model.closeSFTP(host)
                }
            }
        } icon: {
            Image(systemName: "folder.fill")
        }
    }

    private func sessionCloseButton(help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .highPriorityGesture(TapGesture().onEnded(action))
    }

    private func sessionSubtitle(_ phase: ConnectionPhase) -> String {
        switch phase {
        case .connecting: return "SSH · 正在启动 Shell"
        case .connected: return "SSH · 运行中"
        case .failed: return "SSH · 失败"
        case .idle: return "SSH"
        }
    }

    private func sftpSubtitle(_ phase: ConnectionPhase) -> String {
        switch phase {
        case .connecting: return "SFTP · 连接中"
        case .connected: return "SFTP · 运行中"
        case .failed: return "SFTP · 失败"
        case .idle: return "SFTP"
        }
    }
}
