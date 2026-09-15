import AppKit
import SwiftUI
import HostpaneCore

struct HostEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var testStatus: ConnectionTestStatus = .idle
    @State private var testTask: Task<Void, Never>?
    @State private var extraGroups: [String] = []
    @State private var newGroupName = ""
    @State private var showingNewGroup = false
    @State private var showingTagEditor = false

    var body: some View {
        NavigationStack {
            if let editor = model.editor {
                form(editor)
            }
        }
        .frame(minWidth: 520, minHeight: 640)
        .onDisappear { testTask?.cancel() }
    }

    @ViewBuilder
    private func form(_ editor: HostEditorState) -> some View {
        Form {
            identitySection(editor)
            terminalSection(editor)
            classificationSection(editor)
            preferencesSection(editor)
            notesSection(editor)
            Section {
                HStack {
                    Spacer()
                    Button("取消") { cancel() }
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.editor?.record.hostname) { _, _ in
            model.applySSHConfigToEditor()
        }
        .onChange(of: model.editor?.record.name) { _, _ in
            model.applySSHConfigToEditor()
        }
        .navigationTitle(model.hosts.contains(where: { $0.id == editor.record.id }) ? "编辑机器" : "添加机器")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { cancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
            }
        }
        .alert("无法保存", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("新建组", isPresented: $showingNewGroup) {
            TextField("组名", text: $newGroupName)
            Button("添加") { addGroup() }
            Button("取消", role: .cancel) { newGroupName = "" }
        }
        .sheet(isPresented: $showingTagEditor) {
            TagEditorView(
                tags: tagsBinding(editor),
                suggestions: tagSuggestions(editor)
            )
        }
    }

    @ViewBuilder
    private func identitySection(_ editor: HostEditorState) -> some View {
        Section {
            TextField("名称", text: binding(\.record.name, editor))
            TextField("主机名", text: binding(\.record.hostname, editor))
                .textContentType(.URL)
            TextField("用户名", text: binding(\.record.username, editor))
            sshConfigUsernameHint(editor)
            TextField("端口", value: binding(\.record.port, editor), format: .number)
            Picker("认证", selection: binding(\.record.authKind, editor)) {
                ForEach(AuthKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            if !model.keys.isEmpty, editor.record.authKind != .password {
                Picker("SSH 密钥", selection: savedKeyBinding(editor)) {
                    Text("未指定").tag(Optional<UUID>.none)
                    ForEach(model.keys) { key in
                        Text(key.displayName).tag(Optional(key.id))
                    }
                }
            }
            if editor.record.authKind == .privateKey {
                HStack {
                    TextField("私钥路径", text: optionalString(editor, \.privateKeyPath))
                    Button("选择…") { chooseKey(editor) }
                }
                SecureField("密钥口令（可选）", text: binding(\.passphrase, editor))
            }
            if editor.record.authKind == .password {
                SecureField("密码", text: binding(\.password, editor))
            }
            if editor.record.authKind == .agent {
                Text("使用 SSH agent，包括 1Password。本地 ~/.ssh 可以为空。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func terminalSection(_ editor: HostEditorState) -> some View {
        Section("终端") {
            Picker("连接", selection: binding(\.record.connectionKind, editor)) {
                ForEach(HostConnectionKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            Button(action: runTest) {
                Text("测试连接")
                    .frame(maxWidth: .infinity)
            }
            .disabled(testStatus == .running)
            testStatusView
        }
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testStatus {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在测试…")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        case .succeeded:
            Label("连接成功", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func classificationSection(_ editor: HostEditorState) -> some View {
        Section("分类") {
            HStack {
                Picker("组", selection: groupBinding(editor)) {
                    Text("选择组").tag(Optional<String>.none)
                    ForEach(groupOptions(editor), id: \.self) { name in
                        Text(name).tag(Optional(name))
                    }
                }
                Button {
                    newGroupName = ""
                    showingNewGroup = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("新建组")
            }
            HStack {
                Text("标签")
                Spacer()
                if editor.record.tags.isEmpty {
                    Text("无")
                        .foregroundStyle(.secondary)
                } else {
                    Text(editor.record.tags.joined(separator: "、"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button("编辑标签") { showingTagEditor = true }
            }
        }
    }

    @ViewBuilder
    private func preferencesSection(_ editor: HostEditorState) -> some View {
        Section("偏好设置") {
            Toggle("在仪表板中显示状态", isOn: binding(\.record.showOnDashboard, editor))
            TextField("默认 SFTP 路径", text: binding(\.record.defaultSFTPPath, editor))
        }
    }

    @ViewBuilder
    private func notesSection(_ editor: HostEditorState) -> some View {
        Section("备注") {
            TextField("机器备注", text: binding(\.record.notes, editor), axis: .vertical)
                .lineLimit(3...8)
            Text(createdCaption(editor.record.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sshConfigUsernameHint(_ editor: HostEditorState) -> some View {
        let record = (model.editor ?? editor).record
        if let match = model.sshConfigMatch(for: record) {
            if match.username == record.username {
                if (model.editor ?? editor).usernameFromSSHConfig == record.username {
                    Text("已从 ~/.ssh/config 的 Host \(match.name) 填入用户名")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("~/.ssh/config 中 \(match.name) 使用 \(match.username)，和当前用户名冲突")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer(minLength: 8)
                    Button("使用 \(match.username)") {
                        model.applySSHConfigUsernameToEditor()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func cancel() {
        testTask?.cancel()
        model.editor = nil
        dismiss()
    }

    private func save() {
        do {
            try model.saveEditor()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runTest() {
        testTask?.cancel()
        testStatus = .running
        testTask = Task {
            do {
                try await model.probeSSH()
                guard !Task.isCancelled else { return }
                testStatus = .succeeded
            } catch is CancellationError {
                testStatus = .idle
            } catch {
                guard !Task.isCancelled else { return }
                testStatus = .failed(describeSSHError(error))
            }
        }
    }

    private func addGroup() {
        guard let name = HostRecord.normalizedGroup(newGroupName) else { return }
        if !extraGroups.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            extraGroups.append(name)
        }
        guard var next = model.editor else { return }
        next.record.group = name
        model.editor = next
        newGroupName = ""
    }

    private func groupOptions(_ editor: HostEditorState) -> [String] {
        var names = Set(model.knownGroups)
        names.formUnion(extraGroups)
        if let current = HostRecord.normalizedGroup((model.editor ?? editor).record.group) {
            names.insert(current)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func tagSuggestions(_ editor: HostEditorState) -> [String] {
        let current = Set((model.editor ?? editor).record.tags.map { $0.lowercased() })
        return model.knownTags.filter { !current.contains($0.lowercased()) }
    }

    private func createdCaption(_ date: Date) -> String {
        let formatted = date.formatted(
            .dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))
        )
        return "创建于 \(formatted)"
    }

    private func chooseKey(_ editor: HostEditorState) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        panel.prompt = "选择密钥"
        if panel.runModal() == .OK, let url = panel.url {
            guard var next = model.editor else { return }
            next.record.privateKeyPath = url.path
            model.editor = next
        }
    }

    private func binding<T>(
        _ keyPath: WritableKeyPath<HostEditorState, T>,
        _ editor: HostEditorState
    ) -> Binding<T> {
        Binding(
            get: { model.editor?[keyPath: keyPath] ?? editor[keyPath: keyPath] },
            set: { value in
                guard var next = model.editor else { return }
                next[keyPath: keyPath] = value
                model.editor = next
            }
        )
    }

    private func groupBinding(_ editor: HostEditorState) -> Binding<String?> {
        Binding(
            get: { HostRecord.normalizedGroup((model.editor ?? editor).record.group) },
            set: { value in
                guard var next = model.editor else { return }
                next.record.group = HostRecord.normalizedGroup(value)
                model.editor = next
            }
        )
    }

    private func tagsBinding(_ editor: HostEditorState) -> Binding<[String]> {
        Binding(
            get: { (model.editor ?? editor).record.tags },
            set: { value in
                guard var next = model.editor else { return }
                next.record.tags = HostRecord.normalizedTags(value)
                model.editor = next
            }
        )
    }

    private func savedKeyBinding(_ editor: HostEditorState) -> Binding<UUID?> {
        Binding(
            get: {
                let record = (model.editor ?? editor).record
                if let fingerprint = record.sshKeyFingerprint {
                    return model.keys.first { $0.fingerprint == fingerprint }?.id
                }
                if let path = record.privateKeyPath, !path.isEmpty {
                    return model.keys.first { $0.privateKeyPath == path }?.id
                }
                return nil
            },
            set: { id in
                guard var next = model.editor else { return }
                if let key = model.keys.first(where: { $0.id == id }) {
                    next.record.sshKeyFingerprint = key.fingerprint
                    if key.hasPrivateKeyFile {
                        next.record.authKind = .privateKey
                        next.record.privateKeyPath = key.privateKeyPath
                    } else {
                        next.record.authKind = .agent
                        next.record.privateKeyPath = nil
                    }
                } else {
                    next.record.sshKeyFingerprint = nil
                }
                model.editor = next
            }
        )
    }

    private func optionalString(
        _ editor: HostEditorState,
        _ keyPath: WritableKeyPath<HostRecord, String?>
    ) -> Binding<String> {
        Binding(
            get: { (model.editor ?? editor).record[keyPath: keyPath] ?? "" },
            set: { value in
                guard var next = model.editor else { return }
                next.record[keyPath: keyPath] = value.isEmpty ? nil : value
                model.editor = next
            }
        )
    }
}

private enum ConnectionTestStatus: Equatable {
    case idle
    case running
    case succeeded
    case failed(String)
}

private struct TagEditorView: View {
    @Binding var tags: [String]
    var suggestions: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("当前标签") {
                    if tags.isEmpty {
                        Text("还没有标签")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tags, id: \.self) { tag in
                            HStack {
                                Text(tag)
                                Spacer()
                                Button {
                                    tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Section("添加") {
                    HStack {
                        TextField("新标签", text: $draft)
                            .onSubmit(addDraft)
                        Button("添加", action: addDraft)
                            .disabled(HostRecord.normalizedGroup(draft) == nil)
                    }
                }
                if !suggestions.isEmpty {
                    Section("已有标签") {
                        ForEach(suggestions, id: \.self) { tag in
                            Button(tag) {
                                tags = HostRecord.normalizedTags(tags + [tag])
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("编辑标签")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }

    private func addDraft() {
        guard let name = HostRecord.normalizedGroup(draft) else { return }
        tags = HostRecord.normalizedTags(tags + [name])
        draft = ""
    }
}
