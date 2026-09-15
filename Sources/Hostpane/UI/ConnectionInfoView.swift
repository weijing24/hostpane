import AppKit
import SwiftUI
import HostpaneCore

struct ConnectionInfoView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord

    var body: some View {
        let runtime = model.runtime(for: host.id)
        let progress = runtime.progress
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(runtime: runtime)
                endpoint
                steps(progress)
                logs(progress)
                Button(runtime.phase == .connected ? "进入终端" : "关闭") {
                    model.dismissConnectionCard(host)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(22)
            .frame(maxWidth: 760)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(HostpaneTheme.page)
    }

    private func header(runtime: HostRuntime) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(HostpaneTheme.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "terminal.fill")
                    .foregroundStyle(HostpaneTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(host.displayName) · 终端")
                    .font(.headline)
                Text(subtitle(runtime.phase))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var endpoint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("端点")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(host.username)@\(host.hostname):\(host.port)")
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }

    private func steps(_ progress: ConnectionProgress) -> some View {
        HStack(spacing: 8) {
            ForEach(ConnectStep.allCases) { step in
                stepChip(step, state: progress.steps[step] ?? .pending)
            }
        }
    }

    private func stepChip(_ step: ConnectStep, state: ConnectStepState) -> some View {
        HStack(spacing: 6) {
            switch state {
            case .running:
                ProgressView()
                    .controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill")
            case .failed:
                Image(systemName: "xmark.circle.fill")
            case .pending:
                Image(systemName: step.systemImage)
            }
            Text(step.title)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(chipBackground(state), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(chipForeground(state))
    }

    private func chipBackground(_ state: ConnectStepState) -> Color {
        switch state {
        case .running: return HostpaneTheme.accent.opacity(0.12)
        case .done: return Color.green.opacity(0.12)
        case .failed: return Color.red.opacity(0.12)
        case .pending: return Color.secondary.opacity(0.08)
        }
    }

    private func chipForeground(_ state: ConnectStepState) -> Color {
        switch state {
        case .running: return HostpaneTheme.accent
        case .done: return .green
        case .failed: return .red
        case .pending: return .secondary
        }
    }

    private func logs(_ progress: ConnectionProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("连接日志")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(progress.logsVisible ? "隐藏" : "显示") {
                    progress.logsVisible.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if progress.logsVisible {
                HStack {
                    Text("\(progress.logs.count) 个事件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        copyLogs(progress.logs)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sections(progress.logs), id: \.title) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(section.lines) { line in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(dotColor(line))
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 5)
                                    Text(line.formattedLine)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                        .foregroundStyle(line.level == "ERROR" ? Color.red : Color.primary.opacity(0.85))
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func sections(_ lines: [ConnectionLogLine]) -> [(title: String, lines: [ConnectionLogLine])] {
        var result: [(title: String, lines: [ConnectionLogLine])] = []
        for line in lines {
            if result.last?.title == line.sectionTitle {
                result[result.count - 1].lines.append(line)
            } else {
                result.append((line.sectionTitle, [line]))
            }
        }
        return result
    }

    private func dotColor(_ line: ConnectionLogLine) -> Color {
        if line.level == "ERROR" { return .red }
        switch line.category {
        case "authentication": return HostpaneTheme.accent
        case "transport", "connection": return .blue
        default: return HostpaneTheme.accent
        }
    }

    private func copyLogs(_ lines: [ConnectionLogLine]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.map(\.formattedLine).joined(separator: "\n"), forType: .string)
    }

    private func subtitle(_ phase: ConnectionPhase) -> String {
        switch phase {
        case .connecting: return "连接中，正在启动 Shell"
        case .connected: return "已连接"
        case .failed: return "连接失败"
        case .idle: return "未连接"
        }
    }
}
