import AppKit
import SwiftUI
import HostpaneCore

struct KeyEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            if let editor = model.keyEditor {
                form(editor)
            }
        }
        .frame(minWidth: 480, minHeight: editorHeight)
    }

    private var editorHeight: CGFloat {
        model.keyEditor?.mode == .clipboard ? 420 : 320
    }

    @ViewBuilder
    private func form(_ editor: KeyEditorState) -> some View {
        Form {
            TextField("名称", text: binding(\.name, editor))
            switch editor.mode {
            case .addExisting:
                HStack {
                    TextField("私钥或公钥路径", text: binding(\.path, editor))
                    Button("选择…") { chooseKey(editor) }
                }
                Text("可以选私钥、.pub，或 1Password 导出的公钥文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("密钥口令（可选）", text: binding(\.passphrase, editor))
            case .generate:
                TextField("注释", text: binding(\.comment, editor))
                Text("会在 ~/.ssh/<名称> 写入 ssh-keygen -t ed25519。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("密钥口令（可选）", text: binding(\.passphrase, editor))
            case .clipboard:
                TextEditor(text: binding(\.publicKeyText, editor))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                Text("粘贴 OpenSSH 公钥，例如 ssh-ed25519 AAAA…。1Password 里复制公钥即可，不必有 ~/.ssh 文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(title(editor.mode))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    model.keyEditor = nil
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
            }
        }
        .alert("无法保存密钥", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func title(_ mode: KeyEditorState.Mode) -> String {
        switch mode {
        case .generate: return "生成 SSH 密钥"
        case .addExisting: return "从文件导入"
        case .clipboard: return "从剪贴板导入"
        }
    }

    private func save() {
        do {
            try model.saveKeyEditor()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chooseKey(_ editor: KeyEditorState) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            var next = editor
            next.path = url.path
            if next.name.isEmpty {
                next.name = url.lastPathComponent
            }
            model.keyEditor = next
        }
    }

    private func binding(
        _ keyPath: WritableKeyPath<KeyEditorState, String>,
        _ editor: KeyEditorState
    ) -> Binding<String> {
        Binding(
            get: { model.keyEditor?[keyPath: keyPath] ?? editor[keyPath: keyPath] },
            set: { value in
                var next = model.keyEditor ?? editor
                next[keyPath: keyPath] = value
                model.keyEditor = next
            }
        )
    }
}
