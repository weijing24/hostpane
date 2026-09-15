import AppKit
import SwiftUI
import HostpaneCore

struct SFTPHomeView: View {
    var body: some View {
        ContentUnavailableView {
            Label("无会话", systemImage: "folder")
        } description: {
            Text("在机器卡片上把指针移到机器上，点文件夹按钮即可打开 SFTP。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HostpaneTheme.page)
    }
}

struct SFTPBrowserView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    @State private var selection: Set<String> = []
    @State private var mkdirName = ""
    @State private var showMkdir = false
    @State private var renameName = ""
    @State private var renaming: SFTPListingItem?
    @State private var preview: SFTPPreview?
    @State private var confirmDelete = false

    private var runtime: HostRuntime { model.runtime(for: host.id) }

    private var selectedItems: [SFTPListingItem] {
        runtime.sftpListings.filter { selection.contains($0.id) }
    }

    private var sftpStatusTitle: String {
        switch runtime.sftpPhase {
        case .connecting: return "状态: 连接中"
        case .connected: return "状态: 运行中"
        case .failed: return "状态: 失败"
        case .idle: return "状态: 已断开"
        }
    }

    private var hiddenFilesBinding: Binding<Bool> {
        Binding(
            get: { model.settings.sftpShowHiddenFiles },
            set: {
                model.settings.sftpShowHiddenFiles = $0
                model.persistSettings()
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                switch runtime.sftpPhase {
                case .connecting:
                    ProgressView("正在连接 SFTP…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("SFTP 失败", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text(runtime.lastError ?? message)
                    } actions: {
                        Button("重试") { model.startSFTP(host) }
                    }
                case .idle:
                    ContentUnavailableView("SFTP 已断开", systemImage: "folder")
                case .connected:
                    listing
                }
            }
            .background(HostpaneTheme.page)
            .onChange(of: runtime.sftpPath) { _, _ in
                selection = []
            }
            .navigationTitle(host.displayName)
            .navigationSubtitle("SFTP · \(runtime.sftpPath)")
            .toolbar {
                ToolbarItem {
                    Button("上一级", systemImage: "arrow.up.left") {
                        Task { await model.sftpGoUp(host) }
                    }
                    .disabled(runtime.sftpPath == "/" || runtime.sftpBusy)
                    .help("上一级")
                }
                ToolbarItem {
                    Button("刷新", systemImage: "arrow.clockwise") {
                        Task { await model.refreshSFTP(host) }
                    }
                    .disabled(runtime.sftpBusy)
                    .help("刷新")
                }
                ToolbarItem {
                    Button("新建文件夹", systemImage: "folder.badge.plus") {
                        mkdirName = ""
                        showMkdir = true
                    }
                    .disabled(runtime.sftpBusy)
                }
                ToolbarItem {
                    Button("上传", systemImage: "square.and.arrow.up") {
                        pickUploads()
                    }
                    .disabled(runtime.sftpBusy)
                }
                ToolbarItem {
                    Button("下载", systemImage: "square.and.arrow.down") {
                        pickDownloadDestination()
                    }
                    .disabled(selectedItems.isEmpty || runtime.sftpBusy)
                }
                ToolbarItem {
                    Button("删除", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                    .disabled(selectedItems.isEmpty || runtime.sftpBusy)
                }
                ToolbarItem {
                    Menu {
                        Section(sftpStatusTitle) {
                            Button("强制重启", systemImage: "arrow.clockwise") {
                                model.restartSFTP(host)
                            }
                        }
                        Toggle("显示隐藏文件", isOn: hiddenFilesBinding)
                        Divider()
                        Button("上传文件/文件夹", systemImage: "square.and.arrow.up") {
                            pickUploads()
                        }
                        .disabled(runtime.sftpBusy)
                        Button("新建目录", systemImage: "folder.badge.plus") {
                            mkdirName = ""
                            showMkdir = true
                        }
                        .disabled(runtime.sftpBusy)
                        Divider()
                        Button("关闭会话", systemImage: "xmark.circle") {
                            model.closeSFTP(host)
                        }
                    } label: {
                        Label("操作", systemImage: "ellipsis")
                    }
                    .help("操作")
                    .menuIndicator(.visible)
                }
            }
            .onChange(of: model.settings.sftpShowHiddenFiles) { _, _ in
                Task { await model.refreshSFTP(host) }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text(runtime.sftpStatus.isEmpty ? " " : runtime.sftpStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if runtime.sftpBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .alert("新建文件夹", isPresented: $showMkdir) {
                TextField("名称", text: $mkdirName)
                Button("创建") {
                    Task { await model.sftpMakeDirectory(host, name: mkdirName) }
                }
                Button("取消", role: .cancel) {}
            }
            .alert("重命名", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("名称", text: $renameName)
                Button("保存") {
                    if let item = renaming {
                        Task { await model.sftpRename(host, item: item, to: renameName) }
                    }
                    renaming = nil
                }
                Button("取消", role: .cancel) { renaming = nil }
            }
            .alert("删除 \(selectedItems.count) 项？", isPresented: $confirmDelete) {
                Button("删除", role: .destructive) {
                    Task { await model.sftpDelete(host, items: selectedItems) }
                    selection = []
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(selectedItems.map(\.name).joined(separator: "、"))
            }
            .sheet(item: $preview) { item in
                SFTPPreviewSheet(preview: item) {
                    preview = nil
                }
            }
        }
    }

    private var listing: some View {
        VStack(spacing: 0) {
            breadcrumb
            Divider()
            if runtime.sftpListings.isEmpty {
                ContentUnavailableView("这个目录是空的", systemImage: "folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(runtime.sftpListings, selection: $selection) {
                    TableColumn("名称") { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.kind.systemImage)
                                .foregroundStyle(item.kind == .directory ? HostpaneTheme.sftpTint : Color.secondary)
                                .frame(width: 20)
                            Text(item.name)
                                .lineLimit(1)
                        }
                    }
                    TableColumn("大小") { item in
                        Text(sizeText(item))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 64, ideal: 80, max: 110)
                    TableColumn("修改时间") { item in
                        Text(dateText(item.modified))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 120, ideal: 150, max: 200)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    selectionMenu(ids)
                } primaryAction: { ids in
                    openSelection(ids)
                }
            }
        }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                crumb("／", path: "/")
                let parts = SFTPPaths.components(runtime.sftpPath)
                ForEach(Array(parts.enumerated()), id: \.offset) { index, name in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    let path = "/" + parts.prefix(index + 1).joined(separator: "/")
                    crumb(name, path: path)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func crumb(_ title: String, path: String) -> some View {
        Button(title) {
            Task { await model.sftpChangeDirectory(host, path: path) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(path == runtime.sftpPath ? Color.primary : HostpaneTheme.accent)
        .disabled(runtime.sftpBusy)
    }

    @ViewBuilder
    private func selectionMenu(_ ids: Set<String>) -> some View {
        let items = runtime.sftpListings.filter { ids.contains($0.id) }
        if items.count == 1, let item = items.first {
            rowMenu(item)
        } else if !items.isEmpty {
            Button("下载") {
                Task { await model.sftpDownload(host, items: items) }
            }
            Button("删除", role: .destructive) {
                selection = ids
                confirmDelete = true
            }
        }
    }

    private func openSelection(_ ids: Set<String>) {
        guard let id = ids.first,
              let item = runtime.sftpListings.first(where: { $0.id == id })
        else { return }
        Task { await open(item) }
    }

    @ViewBuilder
    private func rowMenu(_ item: SFTPListingItem) -> some View {
        if item.kind == .directory {
            Button("打开") {
                Task { await model.sftpChangeDirectory(host, path: item.path) }
            }
        } else {
            Button("下载") {
                Task { await model.sftpDownload(host, items: [item]) }
            }
            if SFTPPaths.isProbablyText(item.name) {
                Button("预览") {
                    Task { preview = await model.sftpPreview(host, item: item) }
                }
            }
        }
        Button("重命名") {
            renameName = item.name
            renaming = item
        }
        Button("删除", role: .destructive) {
            selection = [item.id]
            confirmDelete = true
        }
    }

    private func open(_ item: SFTPListingItem) async {
        if item.kind == .directory {
            await model.sftpChangeDirectory(host, path: item.path)
            selection = []
            return
        }
        if SFTPPaths.isProbablyText(item.name), item.size ?? 0 < 512 * 1024 {
            preview = await model.sftpPreview(host, item: item)
            if preview != nil { return }
        }
        await model.sftpDownload(host, items: [item])
    }

    private func pickUploads() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "上传"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await model.sftpUpload(host, files: urls) }
    }

    private func pickDownloadDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "保存到此文件夹"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.sftpDownload(host, items: selectedItems, to: url) }
    }

    private func sizeText(_ item: SFTPListingItem) -> String {
        if item.kind == .directory { return "—" }
        guard let size = item.size else { return "—" }
        return formatBytes(size)
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct SFTPPreviewSheet: View {
    let preview: SFTPPreview
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(preview.text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .navigationTitle(preview.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭", action: onClose)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}
