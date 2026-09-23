import AppKit
import SwiftUI
import HostpaneCore

struct SnippetsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selectedPackageID: UUID?
    @State private var packageDraft: PackageDraft?
    @State private var snippetDraft: SnippetDraft?
    @State private var openedSnippetID: UUID?

    var body: some View {
        let packages = filteredPackages
        let snippets = filteredSnippets
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                sectionTitle("包")
                if packages.isEmpty {
                    emptyCard(
                        symbol: "shippingbox",
                        message: "没有可用的代码片段包, 现在创建一个吧!",
                        button: "创建代码片段包"
                    ) {
                        packageDraft = PackageDraft()
                    }
                } else {
                    packageList(packages)
                }

                sectionTitle("代码片段")
                if snippets.isEmpty {
                    emptyCard(
                        symbol: "curlybraces",
                        message: "没有可用的代码片段, 现在创建一个吧!",
                        button: "创建代码片段"
                    ) {
                        snippetDraft = SnippetDraft(packageID: selectedPackageID)
                    }
                } else {
                    snippetList(snippets)
                }
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(HostpaneTheme.page)
        .navigationTitle("代码片段")
        .searchable(text: $query, prompt: "搜索")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("创建代码片段") {
                        snippetDraft = SnippetDraft(packageID: selectedPackageID)
                    }
                    Button("创建包") {
                        packageDraft = PackageDraft()
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("创建")
            }
        }
        .sheet(item: $packageDraft) { draft in
            PackageEditor(draft: draft) { name, note in
                model.addSnippetPackage(name: name, note: note)
            }
        }
        .sheet(item: $snippetDraft) { draft in
            SnippetEditor(draft: draft, packages: model.snippetLibrary.packages) { name, body, note, packageID in
                if let existing = draft.existingID,
                   var snippet = model.snippetLibrary.snippets.first(where: { $0.id == existing }) {
                    snippet.name = name
                    snippet.body = body
                    snippet.note = note
                    snippet.packageID = packageID
                    model.updateCodeSnippet(snippet)
                } else {
                    model.addCodeSnippet(name: name, body: body, note: note, packageID: packageID)
                }
            } onCreatePackage: { name, note in
                model.addSnippetPackage(name: name, note: note)
            }
        }
        .navigationDestination(item: $openedSnippetID) { snippetID in
            SnippetDetailView(snippetID: snippetID)
        }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    private func emptyCard(symbol: String, message: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.title3)
            Button(button, action: action)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    private func packageList(_ packages: [SnippetPackage]) -> some View {
        VStack(spacing: 8) {
            ForEach(packages) { package in
                let count = model.snippetLibrary.snippets.filter { $0.packageID == package.id }.count
                HStack {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(HostpaneTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(package.name)
                        Text("\(count) 个片段")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedPackageID == package.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(HostpaneTheme.accent)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPackageID = selectedPackageID == package.id ? nil : package.id
                }
                .contextMenu {
                    Button("删除包", role: .destructive) {
                        model.deleteSnippetPackage(package.id)
                        if selectedPackageID == package.id { selectedPackageID = nil }
                    }
                }
            }
        }
    }

    private func snippetList(_ snippets: [CodeSnippet]) -> some View {
        VStack(spacing: 8) {
            ForEach(snippets) { snippet in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(snippet.name)
                            .font(.headline)
                        Spacer()
                        if let package = model.snippetLibrary.packages.first(where: { $0.id == snippet.packageID }) {
                            Text(package.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(snippet.body)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .contentShape(Rectangle())
                .onTapGesture { openedSnippetID = snippet.id }
                .contextMenu {
                    Button("复制") { copy(snippet.body) }
                    Button("编辑") {
                        snippetDraft = SnippetDraft(snippet: snippet)
                    }
                    Button("删除", role: .destructive) {
                        model.deleteCodeSnippet(snippet.id)
                    }
                }
            }
        }
    }

    private var filteredPackages: [SnippetPackage] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.snippetLibrary.packages.filter { package in
            needle.isEmpty || package.name.localizedStandardContains(needle)
        }
    }

    private var filteredSnippets: [CodeSnippet] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.snippetLibrary.snippets.filter { snippet in
            if let selectedPackageID, snippet.packageID != selectedPackageID { return false }
            if needle.isEmpty { return true }
            return snippet.name.localizedStandardContains(needle)
                || snippet.body.localizedStandardContains(needle)
                || snippet.note.localizedStandardContains(needle)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct PackageDraft: Identifiable {
    let id = UUID()
    var name = ""
    var note = createdLabel(Date())
    var createdAt = Date()
}

struct SnippetDraft: Identifiable {
    let id = UUID()
    var existingID: UUID?
    var name = ""
    var body = "#!/bin/bash\n"
    var note = ""
    var packageID: UUID?
    var createdAt = Date()

    init(packageID: UUID? = nil) {
        self.packageID = packageID
        let created = Date()
        self.createdAt = created
        self.note = createdLabel(created)
    }

    init(snippet: CodeSnippet) {
        existingID = snippet.id
        name = snippet.name
        body = snippet.body
        note = snippet.note.isEmpty ? createdLabel(snippet.createdAt) : snippet.note
        packageID = snippet.packageID
        createdAt = snippet.createdAt
    }
}

private struct EditorSheet<Content: View>: View {
    var title: String
    var canSave: Bool
    var width: CGFloat = 680
    var height: CGFloat = 480
    var save: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            Divider()
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: width, height: height)
    }
}

private struct PackageEditor: View {
    @State var draft: PackageDraft
    var save: (String, String) -> Void

    var body: some View {
        EditorSheet(
            title: "创建包",
            canSave: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ) {
            save(draft.name, draft.note)
        } content: {
            editorSection("包信息", systemImage: "info.circle") {
                labeledField("名称", text: $draft.name, prompt: "名称")
            }
            editorSection("备注", systemImage: "list.bullet.rectangle") {
                labeledField("包备注", text: $draft.note, prompt: "")
            }
        }
    }
}

struct SnippetEditor: View {
    @State var draft: SnippetDraft
    var packages: [SnippetPackage]
    var save: (String, String, String, UUID?) -> Void
    var onCreatePackage: (String, String) -> Void
    @State private var pickingPackage = false

    var body: some View {
        EditorSheet(
            title: draft.existingID == nil ? "创建代码片段" : "编辑代码片段",
            canSave: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            width: 920,
            height: 860
        ) {
            save(draft.name, draft.body, draft.note, draft.packageID)
        } content: {
            editorSection("代码片段信息", systemImage: "info.circle") {
                labeledField("名称", text: $draft.name, prompt: "名称")
                Divider().padding(.leading, 14)
                HStack {
                    Text("包")
                    Spacer()
                    Button {
                        pickingPackage = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(packageName)
                                .foregroundStyle(draft.packageID == nil ? Color.secondary : Color.primary)
                            Image(systemName: "shippingbox")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            editorSection("代码", systemImage: "chevron.left.forwardslash.chevron.right", expands: true) {
                ShellCodeEditor(text: $draft.body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(6)
            }
            editorSection("备注", systemImage: "list.bullet.rectangle") {
                labeledField("代码片段备注", text: $draft.note, prompt: "")
            }
        }
        .sheet(isPresented: $pickingPackage) {
            PackagePicker { id in
                draft.packageID = id
                pickingPackage = false
            } onCreate: { name, note in
                onCreatePackage(name, note)
            }
        }
    }

    private var packageName: String {
        packages.first { $0.id == draft.packageID }?.name ?? "选择包"
    }
}

private struct PackagePicker: View {
    @Environment(AppModel.self) private var model
    var onSelect: (UUID) -> Void
    var onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            if model.snippetLibrary.packages.isEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("没有可用的代码片段包, 现在创建一个吧!")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                    Button("创建代码片段包") { creating = true }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: 460)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .padding(16)
            } else {
                List(model.snippetLibrary.packages) { package in
                    Button {
                        onSelect(package.id)
                    } label: {
                        HStack {
                            Image(systemName: "shippingbox")
                            Text(package.name)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            HStack {
                Button { creating = true } label: {
                    Label("创建包", systemImage: "plus")
                }
                Spacer()
                Button("取消") { dismiss() }
            }
            .padding(16)
        }
        .frame(width: 620, height: 520)
        .sheet(isPresented: $creating) {
            PackageEditor(draft: PackageDraft()) { name, note in
                onCreate(name, note)
            }
        }
    }
}

private struct ShellCodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let textView = NSTextView()
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.string = text
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.drawsBackground = false
        scroll.documentView = textView
        context.coordinator.highlight(textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        context.coordinator.highlight(textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            highlight(textView)
        }

        func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            storage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: full)
            let body = storage.string as NSString
            var location = 0
            while location < body.length {
                let lineRange = body.lineRange(for: NSRange(location: location, length: 0))
                let line = body.substring(with: lineRange)
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                    storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: lineRange)
                }
                let next = NSMaxRange(lineRange)
                if next <= location { break }
                location = next
            }
        }
    }
}

private func editorSection<Content: View>(
    _ title: String,
    systemImage: String,
    expands: Bool = false,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Label(title, systemImage: systemImage)
            .font(.headline)
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: expands ? .infinity : nil, alignment: .top)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .frame(maxWidth: .infinity, maxHeight: expands ? .infinity : nil, alignment: .top)
}

private func labeledField(_ title: String, text: Binding<String>, prompt: String) -> some View {
    HStack {
        Text(title)
        TextField(prompt, text: text)
            .multilineTextAlignment(.trailing)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
}

private func createdLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "创建于 yyyy年M月d日 H:mm"
    return formatter.string(from: date)
}
