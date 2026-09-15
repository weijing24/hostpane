import SwiftUI
import HostpaneCore

struct DockerEventsView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    let snapshot: DockerSnapshot

    var body: some View {
        let runtime = model.runtime(for: host.id)
        VStack(alignment: .leading, spacing: 14) {
            filterRow(runtime)
            if !runtime.dockerEventsLoaded {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在加载事件…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else if rows(runtime).isEmpty {
                ContentUnavailableView {
                    Label("还没有事件", systemImage: "bell")
                } description: {
                    Text("最近两小时没有匹配的 Docker 事件。")
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(rows(runtime)) { event in
                        DockerEventRow(event: event)
                    }
                }
            }
        }
        .task {
            if !runtime.dockerEventsLoaded {
                await model.refreshDockerEvents(host)
            }
        }
    }

    private func filterRow(_ runtime: HostRuntime) -> some View {
        HStack(spacing: 8) {
            ForEach(DockerEventFilter.allCases) { filter in
                Button {
                    runtime.dockerEventFilter = filter
                } label: {
                    Text(filter.title)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                runtime.dockerEventFilter == filter
                                    ? HostpaneTheme.accent.opacity(0.16)
                                    : Color.secondary.opacity(0.08)
                            )
                        )
                        .foregroundStyle(
                            runtime.dockerEventFilter == filter ? HostpaneTheme.accent : .secondary
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func rows(_ runtime: HostRuntime) -> [DockerEvent] {
        var events = snapshot.events
        switch runtime.dockerEventFilter {
        case .all: break
        case .container: events = events.filter { $0.type == "container" }
        case .image: events = events.filter { $0.type == "image" }
        case .volume: events = events.filter { $0.type == "volume" }
        case .network: events = events.filter { $0.type == "network" }
        }
        let query = runtime.dockerContainerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            events = events.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.image.localizedCaseInsensitiveContains(query)
                    || $0.actor.localizedCaseInsensitiveContains(query)
                    || $0.action.localizedCaseInsensitiveContains(query)
            }
        }
        return events.reversed()
    }
}

private struct DockerEventRow: View {
    let event: DockerEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(HostpaneTheme.docker)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.weight(.medium))
                    .textSelection(.enabled)
                if !event.image.isEmpty {
                    Text(event.image)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 12)
            Text(clockLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var icon: String {
        switch event.type {
        case "image": return "internaldrive"
        case "volume": return "externaldrive.fill"
        case "network": return "globe"
        default: return "shippingbox.fill"
        }
    }

    private var clockLabel: String {
        if event.unixTime > 0 {
            let formatter = DateFormatter()
            formatter.dateFormat = "H:mm:ss"
            return formatter.string(from: Date(timeIntervalSince1970: event.unixTime))
        }
        return event.timestamp
    }
}
