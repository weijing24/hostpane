import SwiftUI
import HostpaneCore

struct HostProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let hostID: UUID
    @State private var showInspect = false
    @State private var showDelete = false
    @State private var stubMessage: String?

    var body: some View {
        Group {
            if let host {
                profile(host)
            } else {
                ContentUnavailableView("机器已删除", systemImage: "server.rack")
            }
        }
        .background(HostpaneTheme.page)
        .navigationTitle(host?.displayName ?? "机器")
        .toolbar {
            if let host {
                ToolbarItem {
                    Button("编辑") { model.beginEditHost(host) }
                }
            }
        }
        .navigationDestination(isPresented: $showInspect) {
            if let host {
                HostInspectView(host: host)
            }
        }
        .alert("删除机器", isPresented: $showDelete) {
            Button("删除", role: .destructive) { deleteHost() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会从 Hostpane 主机簿里移除，不会改 ~/.ssh/config。")
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
    }

    private var host: HostRecord? {
        model.hosts.first { $0.id == hostID }
    }

    @ViewBuilder
    private func profile(_ host: HostRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                profileSection(title: "机器信息", systemImage: "info.circle") {
                    profileRow("名称", host.displayName)
                    Divider().opacity(0.5)
                    profileRow("主机", host.hostname)
                    Divider().opacity(0.5)
                    profileRow("端口", "\(host.port)")
                }
                profileSection(title: "认证", systemImage: "lock.circle") {
                    profileRow("用户名", host.username)
                    if let match = model.sshConfigMatch(for: host), match.username != host.username {
                        Divider().opacity(0.5)
                        HStack(alignment: .firstTextBaseline) {
                            Text("~/.ssh/config 中 \(match.name) 使用 \(match.username)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Spacer(minLength: 8)
                            Button("改用 \(match.username)") {
                                model.applySSHConfigUsername(to: host)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 8)
                    }
                    Divider().opacity(0.5)
                    profileRow("SSH 密钥", authLabel(host))
                }
                profileSection(title: "终端", systemImage: "terminal") {
                    profileRow("连接", host.connectionKind.title)
                }
                profileSection(title: "备注", systemImage: "note.text") {
                    if !host.notes.isEmpty {
                        Text(host.notes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Divider().opacity(0.5)
                    }
                    Text("创建于 \(formattedCreated(host.createdAt))")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                actionRow(host)
                deleteRow
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func profileSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
        }
    }

    private func profileRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }

    private func actionRow(_ host: HostRecord) -> some View {
        HStack(spacing: 10) {
            pill("启动终端") { model.openTerminal(host) }
            pill("启动 SFTP") { model.openSFTP(host) }
            pill("端口转发") { stubMessage = "端口转发还没接上。" }
            pill("状态监控") { showInspect = true }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var deleteRow: some View {
        HStack {
            pill("删除机器", destructive: true) { showDelete = true }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func pill(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(destructive ? Color.red : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    private func authLabel(_ host: HostRecord) -> String {
        if let fingerprint = host.sshKeyFingerprint,
           let key = model.keys.first(where: { $0.fingerprint == fingerprint }) {
            return key.displayName
        }
        switch host.authKind {
        case .agent:
            return "SSH agent"
        case .password:
            return "密码"
        case .privateKey:
            if let path = host.privateKeyPath, !path.isEmpty {
                if let key = model.keys.first(where: { $0.privateKeyPath == path }) {
                    return key.displayName
                }
                return URL(fileURLWithPath: path).lastPathComponent
            }
            return "私钥"
        }
    }

    private func formattedCreated(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func deleteHost() {
        guard let host else { return }
        try? model.deleteHost(host)
        dismiss()
    }
}
