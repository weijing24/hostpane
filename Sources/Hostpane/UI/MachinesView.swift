import SwiftUI
import HostpaneCore

struct MachinesView: View {
    @Environment(AppModel.self) private var model
    @State private var inspectedHostID: UUID?
    @State private var showDeleteConfirm = false
    @State private var showGroupAlert = false
    @State private var showTagAlert = false
    @State private var groupDraft = ""
    @State private var tagDraft = ""

    var body: some View {
        @Bindable var model = model
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip("全部", selected: model.machineFilter == .all) {
                                model.machineFilter = .all
                            }
                            filterChip("无标签", selected: model.machineFilter == .untagged) {
                                model.machineFilter = .untagged
                            }
                            ForEach(model.knownTags, id: \.self) { tag in
                                filterChip(tag, selected: model.machineFilter == .tag(tag)) {
                                    model.machineFilter = .tag(tag)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                if model.hosts.isEmpty {
                    ContentUnavailableView {
                        Label("还没有机器", systemImage: "server.rack")
                    } description: {
                        Text("添加一台机器，或从 ~/.ssh/config 导入 Host。")
                    } actions: {
                        Button("添加机器") { model.beginAddHost() }
                        Button("导入 SSH Config") { model.beginImportSSHConfig() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else if model.filteredHosts.isEmpty {
                    ContentUnavailableView {
                        Label("没有匹配的机器", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("试试其他标签，或清空搜索。")
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                        ForEach(model.filteredHosts) { host in
                            MachineCard(
                                host: host,
                                batchEditing: model.isBatchEditing,
                                selected: model.selectedHostIDs.contains(host.id)
                            ) {
                                if model.isBatchEditing {
                                    model.toggleHostSelection(host.id)
                                } else {
                                    inspectedHostID = host.id
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(HostpaneTheme.page)
        .navigationTitle(model.isBatchEditing ? "已选 \(model.selectedHostIDs.count) 台" : "机器")
        .toolbar {
            if model.isBatchEditing {
                ToolbarItem {
                    Button("全选") { model.selectAllFilteredHosts() }
                }
                ToolbarItem {
                    Button("设置组") {
                        groupDraft = ""
                        showGroupAlert = true
                    }
                    .disabled(model.selectedHostIDs.isEmpty)
                }
                ToolbarItem {
                    Button("添加标签") {
                        tagDraft = ""
                        showTagAlert = true
                    }
                    .disabled(model.selectedHostIDs.isEmpty)
                }
                ToolbarItem {
                    Button("删除", role: .destructive) { showDeleteConfirm = true }
                        .disabled(model.selectedHostIDs.isEmpty)
                }
                ToolbarItem {
                    Button("完成") { model.endBatchEditing() }
                }
            } else {
                ToolbarItem {
                    Button("批量管理") { model.beginBatchEditing() }
                        .disabled(model.hosts.isEmpty)
                }
                ToolbarItem {
                    Menu {
                        Button("添加机器") { model.beginAddHost() }
                        Button("导入 SSH Config") { model.beginImportSSHConfig() }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem {
                    TextField("搜索", text: $model.machineSearch)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            }
        }
        .alert("删除机器", isPresented: $showDeleteConfirm) {
            Button("删除 \(model.selectedHostIDs.count) 台", role: .destructive) {
                try? model.deleteSelectedHosts()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会从 Hostpane 主机簿里移除，不会改 ~/.ssh/config。")
        }
        .alert("设置组", isPresented: $showGroupAlert) {
            TextField("组名，留空则清除", text: $groupDraft)
            Button("应用") { model.setGroupForSelected(groupDraft) }
            Button("取消", role: .cancel) {}
        }
        .alert("添加标签", isPresented: $showTagAlert) {
            TextField("标签", text: $tagDraft)
            Button("添加") { model.addTagToSelected(tagDraft) }
            Button("取消", role: .cancel) {}
        }
        .navigationDestination(item: $inspectedHostID) { id in
            HostProfileView(hostID: id)
        }
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().stroke(selected ? HostpaneTheme.accent.opacity(0.7) : Color.secondary.opacity(0.25))
                )
                .foregroundStyle(selected ? HostpaneTheme.accent : .secondary)
        }
        .buttonStyle(.plain)
    }
}

private struct MachineCard: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    var batchEditing: Bool
    var selected: Bool
    var onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if batchEditing {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? HostpaneTheme.accent : .secondary)
                    .frame(width: 28)
            } else {
                Image(systemName: "server.rack")
                    .font(.title3)
                    .foregroundStyle(HostpaneTheme.accent)
                    .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(host.displayName)
                    .font(.headline)
                Text(host.hostname)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let group = host.group, !group.isEmpty {
                    Text(group)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if host.tags.isEmpty {
                        tagCapsule("无标签")
                    } else {
                        ForEach(host.tags, id: \.self) { tag in
                            tagCapsule(tag)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            if hovering, !batchEditing {
                HStack(spacing: 8) {
                    CircleActionButton.terminal { model.openTerminal(host) }
                    CircleActionButton.sftp { model.openSFTP(host) }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    (selected || hovering) ? HostpaneTheme.accent.opacity(0.7) : Color.secondary.opacity(0.12),
                    lineWidth: 1.5
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("查看详情") { onOpen() }
            Button("打开终端") { model.openTerminal(host) }
            Button("打开 SFTP") { model.openSFTP(host) }
            Button("打开 Docker") { model.openDocker(host) }
            Button("编辑") { model.beginEditHost(host) }
            Divider()
            Button("删除", role: .destructive) { try? model.deleteHost(host) }
        }
    }

    private func tagCapsule(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.08)))
            .foregroundStyle(.secondary)
    }
}

struct CircleActionButton: View {
    var systemImage: String
    var idleFill: Color
    var activeFill: Color
    var idleForeground: Color
    var activeForeground: Color
    var help: String
    var action: () -> Void
    @State private var hovering = false

    static func terminal(action: @escaping () -> Void) -> CircleActionButton {
        CircleActionButton(
            systemImage: "terminal.fill",
            idleFill: HostpaneTheme.accent.opacity(0.16),
            activeFill: HostpaneTheme.accent,
            idleForeground: HostpaneTheme.accent,
            activeForeground: .white,
            help: "终端",
            action: action
        )
    }

    static func sftp(action: @escaping () -> Void) -> CircleActionButton {
        CircleActionButton(
            systemImage: "folder.fill",
            idleFill: HostpaneTheme.sftpAccent.opacity(0.16),
            activeFill: HostpaneTheme.sftpAccent,
            idleForeground: HostpaneTheme.sftpAccent,
            activeForeground: .white,
            help: "SFTP",
            action: action
        )
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(hovering ? activeForeground : idleForeground)
                .frame(width: 36, height: 36)
                .background(Circle().fill(hovering ? activeFill : idleFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}
