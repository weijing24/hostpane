import SwiftUI
import HostpaneCore

struct DockerVolumesView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    let snapshot: DockerSnapshot

    var body: some View {
        let runtime = model.runtime(for: host.id)
        let rows = filtered(runtime)
        if rows.isEmpty {
            ContentUnavailableView {
                Label("没有卷", systemImage: "externaldrive")
            } description: {
                Text("试试其他关键字。")
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(rows) { volume in
                    DockerVolumeCard(
                        volume: volume,
                        users: volume.usedBy(snapshot.containers)
                    ) {
                        runtime.dockerSelectedVolumeID = volume.name
                        Task { await model.refreshDockerVolumeInspect(host, name: volume.name) }
                    }
                    .contextMenu {
                        Button("删除", role: .destructive) {
                            Task { await model.dockerRemoveVolume(host, name: volume.name) }
                        }
                    }
                }
            }
        }
    }

    private func filtered(_ runtime: HostRuntime) -> [DockerVolume] {
        let query = runtime.dockerContainerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return snapshot.volumes }
        return snapshot.volumes.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.driver.localizedCaseInsensitiveContains(query)
                || $0.mountpoint.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct DockerVolumeCard: View {
    let volume: DockerVolume
    let users: [DockerContainer]
    var onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "externaldrive.fill")
                        .foregroundStyle(HostpaneTheme.docker)
                    Text(volume.name)
                        .font(.headline)
                        .foregroundStyle(HostpaneTheme.docker)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                HStack {
                    Text(volume.driver.isEmpty ? "local" : volume.driver)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    usageBadge
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(hovering ? HostpaneTheme.docker.opacity(0.45) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var usageBadge: some View {
        if users.isEmpty {
            Text("未使用")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(HostpaneTheme.loadMedium.opacity(0.18)))
                .foregroundStyle(HostpaneTheme.loadMedium)
        } else {
            Text("\(users.count) 个容器")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(HostpaneTheme.online.opacity(0.16)))
                .foregroundStyle(HostpaneTheme.online)
        }
    }
}

struct DockerVolumeDetailView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    let volumeName: String
    @State private var showInspect = false

    var body: some View {
        let runtime = model.runtime(for: host.id)
        let volume = runtime.dockerSnapshot?.volumes.first { $0.name == volumeName }
        let users = volume?.usedBy(runtime.dockerSnapshot?.containers ?? []) ?? []
        ScrollView {
            if let volume {
                VStack(alignment: .leading, spacing: 22) {
                    infoSection(volume)
                    if volume.inspectLoaded {
                        if !volume.labels.isEmpty {
                            labelsSection(volume)
                        }
                    }
                    if !users.isEmpty {
                        usersSection(users)
                    }
                    actionsSection(volume)
                }
                .padding(24)
                .frame(maxWidth: 820, alignment: .leading)
            } else {
                ContentUnavailableView("找不到这个卷", systemImage: "externaldrive")
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .background(HostpaneTheme.page)
        .navigationTitle(volume?.name ?? "卷")
        .navigationDestination(isPresented: $showInspect) {
            DockerTextPage(host: host, containerName: volumeName, kind: .inspect)
        }
        .task {
            await model.refreshDockerVolumeInspect(host, name: volumeName)
        }
    }

    private func infoSection(_ volume: DockerVolume) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("卷信息", systemImage: "info.circle")
                .font(.headline)
            VStack(spacing: 0) {
                infoRow("名称", volume.name, monospaced: true)
                infoRow("驱动", volume.driver.isEmpty ? "—" : volume.driver)
                infoRow("范围", volume.scope.isEmpty ? (volume.inspectLoaded ? "—" : "…") : volume.scope)
                infoRow("挂载点", volume.mountpoint.isEmpty ? "—" : volume.mountpoint, monospaced: true)
                infoRow(
                    "创建于",
                    volume.createdAt.isEmpty
                        ? (volume.inspectLoaded ? "—" : "…")
                        : formatDockerCreated(volume.createdAt)
                )
            }
            .background(cardBackground)
        }
    }

    private func labelsSection(_ volume: DockerVolume) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("标签", systemImage: "tag")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(volume.labels) { label in
                    HStack(alignment: .firstTextBaseline) {
                        Text(label.key)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Spacer(minLength: 12)
                        Text(label.value)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .background(cardBackground)
        }
    }

    private func usersSection(_ users: [DockerContainer]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("使用方", systemImage: "shippingbox")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(users) { item in
                    Button {
                        model.runtime(for: host.id).dockerSelectedContainerID = item.id
                    } label: {
                        HStack {
                            Circle()
                                .fill(item.isRunning ? HostpaneTheme.online : Color.secondary.opacity(0.5))
                                .frame(width: 8, height: 8)
                            Text(item.name)
                            Spacer()
                            Text(item.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(cardBackground)
        }
    }

    private func actionsSection(_ volume: DockerVolume) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("操作", systemImage: "hammer")
                .font(.headline)
            VStack(spacing: 0) {
                actionRow("检查", "eye") { showInspect = true }
                actionRow("删除", "trash", destructive: true) {
                    Task { await model.dockerRemoveVolume(host, name: volume.name) }
                }
            }
            .background(cardBackground)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
    }

    private func infoRow(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .body)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func actionRow(_ title: String, _ icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
