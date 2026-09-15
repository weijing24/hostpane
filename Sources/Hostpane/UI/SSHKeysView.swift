import AppKit
import SwiftUI
import HostpaneCore

struct SSHKeysView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if filtered.isEmpty {
                ContentUnavailableView {
                    Label(model.keys.isEmpty ? "还没有 SSH 密钥" : "没有匹配的密钥", systemImage: "key")
                } description: {
                    Text("密钥可以只在 1Password / SSH agent 里，不必出现在 ~/.ssh。可生成新密钥，或从剪贴板、文件导入公钥。")
                } actions: {
                    if model.keys.isEmpty {
                        Button("生成 SSH 密钥") { model.beginGenerateKey() }
                        Button("从剪贴板导入") { importClipboard() }
                        Button("从文件导入") { importFile() }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        ForEach(filtered) { key in
                            SSHKeyCard(key: key)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(HostpaneTheme.page)
        .navigationTitle("SSH 密钥")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("生成 SSH 密钥") { model.beginGenerateKey() }
                    Divider()
                    Button("从剪贴板导入") { importClipboard() }
                    Button("从文件导入") { importFile() }
                } label: {
                    Image(systemName: "plus")
                }
                .help("添加密钥")
            }
            ToolbarItem {
                TextField("搜索", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
        }
        .task { await model.refreshAgentKeys() }
        .alert("无法导入密钥", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var filtered: [SSHKeyRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.keys }
        return model.keys.filter { key in
            key.displayName.localizedCaseInsensitiveContains(query)
                || key.shortType.localizedCaseInsensitiveContains(query)
                || key.fingerprint.localizedCaseInsensitiveContains(query)
                || key.comment.localizedCaseInsensitiveContains(query)
        }
    }

    private func importClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        model.beginImportClipboard(text: text)
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "导入"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try model.importKey(fromFilePath: url.path)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SSHKeyCard: View {
    @Environment(AppModel.self) private var model
    let key: SSHKeyRecord

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "key.fill")
                .font(.title3)
                .foregroundStyle(HostpaneTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(key.displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(key.shortType)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(badgeColor.opacity(0.16)))
                        .foregroundStyle(badgeColor)
                    Text(originLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .contextMenu {
            if !key.publicKey.isEmpty {
                Button("复制公钥") { copyPublicKey() }
            }
            if key.hasPrivateKeyFile {
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: key.privateKeyPath)]
                    )
                }
            }
            Divider()
            Button("从 Hostpane 删除", role: .destructive) {
                try? model.deleteKey(key)
            }
        }
    }

    private var badgeColor: Color {
        switch key.shortType {
        case "RSA": return Color.orange
        case "ED25519": return HostpaneTheme.online
        case "ECDSA": return HostpaneTheme.cpuUser
        default: return .secondary
        }
    }

    private var originLabel: String {
        switch key.origin {
        case .agent: return "SSH agent"
        case .clipboard: return "剪贴板"
        case .generated: return "已生成"
        case .file: return key.hasPrivateKeyFile ? "文件" : "公钥"
        }
    }

    private func copyPublicKey() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(key.publicKey, forType: .string)
    }
}
