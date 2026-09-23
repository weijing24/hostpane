import SwiftUI
import HostpaneCore

struct SnippetDetailView: View {
    @Environment(AppModel.self) private var model
    var snippetID: UUID
    @State private var editing = false
    @State private var choosingTargets = false
    @State private var selectedRun: SnippetRun?

    private var snippet: CodeSnippet? {
        model.snippetLibrary.snippets.first { $0.id == snippetID }
    }

    var body: some View {
        Group {
            if let snippet {
                detail(snippet)
            } else {
                ContentUnavailableView("代码片段已删除", systemImage: "curlybraces")
            }
        }
        .background(HostpaneTheme.page)
        .navigationTitle("代码片段详情")
        .toolbar {
            if snippet != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("编辑") { editing = true }
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let snippet {
                SnippetEditor(draft: SnippetDraft(snippet: snippet), packages: model.snippetLibrary.packages) { name, body, note, packageID in
                    var updated = snippet
                    updated.name = name
                    updated.body = body
                    updated.note = note
                    updated.packageID = packageID
                    model.updateCodeSnippet(updated)
                } onCreatePackage: { name, note in
                    model.addSnippetPackage(name: name, note: note)
                }
            }
        }
        .sheet(isPresented: $choosingTargets) {
            if let snippet {
                SnippetTargetPicker(snippet: snippet)
            }
        }
        .sheet(item: $selectedRun) { run in
            NavigationStack {
                ScrollView {
                    Text(run.output.isEmpty ? "没有输出。" : run.output)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                .navigationTitle(run.summary)
            }
            .frame(minWidth: 560, minHeight: 420)
        }
    }

    private func detail(_ snippet: CodeSnippet) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("代码片段信息", systemImage: "info.circle") {
                    infoRow("名称", snippet.name)
                }
                section("运行", systemImage: "paperplane") {
                    VStack(spacing: 0) {
                        Button("执行代码片段") { choosingTargets = true }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                        Divider()
                        NavigationLink {
                            SnippetHistoryView(snippetID: snippet.id) { run in
                                selectedRun = run
                            }
                        } label: {
                            HStack {
                                Text("代码片段执行历史")
                                Spacer()
                                Text("\(model.snippetRuns(snippet.id).count)")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                section("代码", systemImage: "chevron.left.forwardslash.chevron.right") {
                    Text(snippet.body)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                section("备注", systemImage: "list.bullet.rectangle") {
                    Text(snippet.note.isEmpty ? "无" : snippet.note)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .foregroundStyle(snippet.note.isEmpty ? .secondary : .primary)
                }
            }
            .padding(28)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private func section<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
        }
        .padding(14)
    }
}

struct SnippetHistoryView: View {
    @Environment(AppModel.self) private var model
    var snippetID: UUID
    var open: (SnippetRun) -> Void

    var body: some View {
        let runs = model.snippetRuns(snippetID)
        Group {
            if runs.isEmpty {
                ContentUnavailableView("还没有执行记录", systemImage: "clock")
            } else {
                List(runs) { run in
                    Button {
                        open(run)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(run.summary)
                            Text(run.startedAt.formatted(date: .abbreviated, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("代码片段执行历史")
    }
}

struct SnippetTargetPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var snippet: CodeSnippet
    @State private var selectedGroups: Set<String> = []
    @State private var selectedHosts: Set<UUID> = []
    @State private var running = false
    @State private var finished: SnippetRun?

    var body: some View {
        VStack(spacing: 0) {
            Text("选择机器")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("组")
                        .font(.headline)
                    if model.knownGroups.isEmpty {
                        emptyCard("没有可用的机器组，立即创建一个吧！")
                    } else {
                        targetCard {
                            ForEach(model.knownGroups, id: \.self) { group in
                                toggleRow(group, selected: selectedGroups.contains(group)) {
                                    toggleGroup(group)
                                }
                            }
                        }
                    }
                    Text("机器")
                        .font(.headline)
                    if model.hosts.isEmpty {
                        emptyCard("没有可用的机器，立即创建一台吧！")
                    } else {
                        targetCard {
                            ForEach(model.hosts) { host in
                                toggleRow(host.displayName, selected: selectedHosts.contains(host.id)) {
                                    toggleHost(host.id)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            Button {
                Task { await execute() }
            } label: {
                Text(running ? "正在执行…" : "在 \(resolvedHosts.count) 台机器 和 \(selectedGroups.count) 个组 上执行")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(HostpaneTheme.accent)
            .disabled(resolvedHosts.isEmpty || running)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Divider()
                .padding(.top, 12)
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .disabled(running)
            }
            .padding(16)
        }
        .frame(width: 560, height: 720)
        .sheet(item: $finished) { run in
            NavigationStack {
                ScrollView {
                    Text(run.output.isEmpty ? "没有输出。" : run.output)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                .navigationTitle(run.summary)
            }
            .frame(minWidth: 560, minHeight: 420)
        }
    }

    private var resolvedHosts: [HostRecord] {
        var ids = selectedHosts
        for group in selectedGroups {
            for host in model.hosts where host.group == group {
                ids.insert(host.id)
            }
        }
        return model.hosts.filter { ids.contains($0.id) }
    }

    private func toggleGroup(_ group: String) {
        if selectedGroups.contains(group) {
            selectedGroups.remove(group)
        } else {
            selectedGroups.insert(group)
        }
    }

    private func toggleHost(_ id: UUID) {
        if selectedHosts.contains(id) {
            selectedHosts.remove(id)
        } else {
            selectedHosts.insert(id)
        }
    }

    private func execute() async {
        running = true
        let run = await model.executeSnippet(snippet, hosts: resolvedHosts)
        running = false
        finished = run
    }

    private func emptyCard(_ message: String) -> some View {
        Text(message)
            .font(.title3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
    }

    private func targetCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    private func toggleRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? HostpaneTheme.accent : Color.secondary)
                Text(title)
                Spacer()
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
