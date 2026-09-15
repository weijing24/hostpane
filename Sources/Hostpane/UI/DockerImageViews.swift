import SwiftUI
import HostpaneCore

struct DockerImagesView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    let snapshot: DockerSnapshot

    var body: some View {
        let runtime = model.runtime(for: host.id)
        let rows = filtered(runtime)
        if rows.isEmpty {
            ContentUnavailableView {
                Label("没有镜像", systemImage: "internaldrive")
            } description: {
                Text("试试其他关键字。")
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(rows) { image in
                    DockerImageCard(
                        image: image,
                        users: image.usedBy(snapshot.containers)
                    ) {
                        runtime.dockerSelectedImageID = image.id
                        Task { await model.refreshDockerImageInspect(host, imageID: image.id) }
                    }
                    .contextMenu {
                        Button("删除", role: .destructive) {
                            Task { await model.dockerRemoveImage(host, image: image) }
                        }
                    }
                }
            }
        }
    }

    private func filtered(_ runtime: HostRuntime) -> [DockerImage] {
        let query = runtime.dockerContainerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return snapshot.images }
        return snapshot.images.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.shortID.localizedCaseInsensitiveContains(query)
                || $0.digest.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct DockerImageCard: View {
    let image: DockerImage
    let users: [DockerContainer]
    var onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(HostpaneTheme.docker)
                    Text(image.displayName)
                        .font(.headline)
                        .foregroundStyle(HostpaneTheme.docker)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(image.shortID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    usageBadge
                }
                HStack {
                    Text("创建于 \(formatDockerSince(image.created))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatImageSize(image.sizeLabel))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
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
        if image.isDangling {
            Text("悬空")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(HostpaneTheme.loadMedium.opacity(0.18)))
                .foregroundStyle(HostpaneTheme.loadMedium)
        } else if users.isEmpty {
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

struct DockerImageDetailView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    let imageID: String
    @State private var historyExpanded = false
    @State private var showTagSheet = false
    @State private var tagDraft = ""
    @State private var showInspect = false

    var body: some View {
        let runtime = model.runtime(for: host.id)
        let image = runtime.dockerSnapshot?.images.first { $0.id == imageID }
        let users = image?.usedBy(runtime.dockerSnapshot?.containers ?? []) ?? []
        ScrollView {
            if let image {
                VStack(alignment: .leading, spacing: 22) {
                    infoSection(image)
                    tagsSection(image)
                    if !users.isEmpty {
                        usersSection(users)
                    }
                    historySection(image)
                    actionsSection(image)
                }
                .padding(24)
                .frame(maxWidth: 820, alignment: .leading)
            } else {
                ContentUnavailableView("找不到这个镜像", systemImage: "internaldrive")
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .background(HostpaneTheme.page)
        .navigationTitle(image?.displayName ?? "镜像")
        .navigationDestination(isPresented: $showInspect) {
            DockerTextPage(host: host, containerName: image?.reference ?? imageID, kind: .inspect)
        }
        .sheet(isPresented: $showTagSheet) {
            tagSheet(image)
        }
        .task {
            await model.refreshDockerImageInspect(host, imageID: imageID)
        }
    }

    private func infoSection(_ image: DockerImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("镜像信息", systemImage: "info.circle")
                .font(.headline)
            VStack(spacing: 0) {
                infoRow("ID", image.shortID)
                infoRow("创建于", formatDockerCreated(image.createdAt.isEmpty ? image.created : image.createdAt))
                infoRow("大小", formatImageSize(image.sizeLabel))
                if !image.sharedSizeLabel.isEmpty {
                    infoRow("共享大小", formatImageSize(image.sharedSizeLabel))
                }
                if !image.digestLine.isEmpty {
                    infoRow("摘要", image.digestLine, monospaced: true)
                }
            }
            .background(cardBackground)
        }
    }

    private func tagsSection(_ image: DockerImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("标签", systemImage: "tag")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(image.repoTags.isEmpty ? [image.displayName] : image.repoTags, id: \.self) { tag in
                    Text(tag)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func historySection(_ image: DockerImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("历史记录", systemImage: "square.stack.3d.up")
                .font(.headline)
            Group {
                if !image.historyLoaded {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在加载层…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    DisclosureGroup(isExpanded: $historyExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(image.layers.enumerated()), id: \.offset) { _, layer in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(layer.createdBy)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                    Text(formatImageSize(layer.sizeLabel))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("\(image.layers.count) 个层")
                    }
                }
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    private func actionsSection(_ image: DockerImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("操作", systemImage: "hammer")
                .font(.headline)
            VStack(spacing: 0) {
                actionRow("标签", "tag") {
                    tagDraft = image.isDangling ? "" : "\(image.repository):"
                    showTagSheet = true
                }
                actionRow("检查", "eye") { showInspect = true }
                actionRow("删除", "trash", destructive: true) {
                    Task { await model.dockerRemoveImage(host, image: image) }
                }
            }
            .background(cardBackground)
        }
    }

    private func tagSheet(_ image: DockerImage?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加标签")
                .font(.headline)
            TextField("仓库:标签", text: $tagDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { showTagSheet = false }
                Button("添加") {
                    if let image {
                        Task { await model.dockerTagImage(host, image: image, target: tagDraft) }
                    }
                    showTagSheet = false
                }
                .disabled(tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
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

func formatImageSize(_ raw: String) -> String {
    if let bytes = parseDataSize(raw) ?? parseDockerSize(raw) {
        return formatInspectBytes(bytes)
    }
    return raw
}

func formatDockerSince(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    let replacements: [(String, String)] = [
        ("about a minute ago", "1 分钟前"),
        ("about an hour ago", "1 小时前"),
        ("less than a second ago", "刚刚"),
        ("weeks ago", "周前"),
        ("week ago", "周前"),
        ("months ago", "个月前"),
        ("month ago", "个月前"),
        ("days ago", "天前"),
        ("day ago", "天前"),
        ("hours ago", "小时前"),
        ("hour ago", "小时前"),
        ("minutes ago", "分钟前"),
        ("minute ago", "分钟前"),
        ("seconds ago", "秒前")
    ]
    var result = lower
    for (english, chinese) in replacements where result.contains(english) {
        result = result.replacingOccurrences(of: english, with: chinese)
        break
    }
    if result == lower { return trimmed }
    return result.replacingOccurrences(of: "  ", with: " ")
}
