import SwiftUI
import HostpaneCore

struct DockerNetworksView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    let snapshot: DockerSnapshot

    var body: some View {
        let runtime = model.runtime(for: host.id)
        let rows = filtered(runtime)
        if rows.isEmpty {
            ContentUnavailableView {
                Label("没有网络", systemImage: "globe")
            } description: {
                Text("试试其他关键字。")
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(rows) { network in
                    DockerNetworkCard(
                        network: network,
                        users: network.usedBy(snapshot.containers)
                    ) {
                        runtime.dockerSelectedNetworkID = network.name
                        Task { await model.refreshDockerNetworkInspect(host, name: network.name) }
                    }
                    .contextMenu {
                        if !network.isBuiltin {
                            Button("删除", role: .destructive) {
                                Task { await model.dockerRemoveNetwork(host, name: network.name) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func filtered(_ runtime: HostRuntime) -> [DockerNetwork] {
        let query = runtime.dockerContainerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return snapshot.networks }
        return snapshot.networks.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.driver.localizedCaseInsensitiveContains(query)
                || $0.subnet.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct DockerNetworkCard: View {
    let network: DockerNetwork
    let users: [DockerContainer]
    var onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(HostpaneTheme.docker)
                    Text(network.name)
                        .font(.headline)
                        .foregroundStyle(HostpaneTheme.docker)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 6) {
                    Text(network.driver.isEmpty ? "—" : network.driver)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if network.isBuiltin {
                        Text("内置")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    usageBadge
                }
                HStack {
                    Text("子网")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(network.subnet.isEmpty ? "—" : network.subnet)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
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
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                .foregroundStyle(.secondary)
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

struct DockerNetworkDetailView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    let networkName: String
    @State private var showInspect = false

    var body: some View {
        let runtime = model.runtime(for: host.id)
        let network = runtime.dockerSnapshot?.networks.first { $0.name == networkName }
        let users = network?.usedBy(runtime.dockerSnapshot?.containers ?? []) ?? []
        ScrollView {
            if let network {
                VStack(alignment: .leading, spacing: 22) {
                    infoSection(network)
                    if !network.subnet.isEmpty || !network.gateway.isEmpty {
                        ipamSection(network)
                    }
                    if !users.isEmpty {
                        usersSection(users)
                    }
                    actionsSection(network)
                }
                .padding(24)
                .frame(maxWidth: 820, alignment: .leading)
            } else {
                ContentUnavailableView("找不到这个网络", systemImage: "globe")
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .background(HostpaneTheme.page)
        .navigationTitle(network?.name ?? "网络")
        .navigationDestination(isPresented: $showInspect) {
            DockerTextPage(host: host, containerName: networkName, kind: .inspect)
        }
        .task {
            await model.refreshDockerNetworkInspect(host, name: networkName)
        }
    }

    private func infoSection(_ network: DockerNetwork) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("网络信息", systemImage: "info.circle")
                .font(.headline)
            VStack(spacing: 0) {
                infoRow("名称", network.name)
                infoRow("ID", network.shortID)
                infoRow("驱动", network.driver.isEmpty ? "—" : network.driver)
                infoRow("范围", network.scope.isEmpty ? "—" : network.scope)
            }
            .background(cardBackground)
        }
    }

    private func ipamSection(_ network: DockerNetwork) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("IPAM", systemImage: "network")
                .font(.headline)
            VStack(spacing: 0) {
                infoRow("子网", network.subnet.isEmpty ? "—" : network.subnet)
                infoRow("网关", network.gateway.isEmpty ? "—" : network.gateway)
            }
            .background(cardBackground)
        }
    }

    private func usersSection(_ users: [DockerContainer]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("已连接的容器", systemImage: "shippingbox")
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

    private func actionsSection(_ network: DockerNetwork) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("操作", systemImage: "hammer")
                .font(.headline)
            VStack(spacing: 0) {
                actionRow("检查", "eye") { showInspect = true }
                if !network.isBuiltin {
                    actionRow("删除", "trash", destructive: true) {
                        Task { await model.dockerRemoveNetwork(host, name: network.name) }
                    }
                }
            }
            .background(cardBackground)
            if network.isBuiltin {
                Text("无法删除内置网络。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
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
