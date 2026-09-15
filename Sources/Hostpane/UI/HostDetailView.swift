import SwiftUI
import HostpaneCore

struct HostDetailView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord

    var body: some View {
        let runtime = model.runtime(for: host.id)
        Group {
            switch runtime.phase {
            case .connected:
                connectedLayout(runtime: runtime)
            case .connecting:
                idleLayout(runtime: runtime, connecting: true)
            case .idle, .failed:
                idleLayout(runtime: runtime, connecting: false)
            }
        }
        .navigationTitle(host.displayName)
        .toolbar {
            ToolbarItemGroup {
                Button("Edit") { model.beginEditHost(host) }
                if runtime.phase == .connected || runtime.phase == .connecting {
                    Button("Disconnect") { model.disconnect(host) }
                } else {
                    Button("Connect") { model.connect(host) }
                        .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }
    }

    @ViewBuilder
    private func connectedLayout(runtime: HostRuntime) -> some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 16) {
                header(runtime: runtime)
                if let error = runtime.lastError, !error.isEmpty {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                MetricsGridView(metrics: runtime.metrics, phase: runtime.phase)
            }
            .padding(20)
            .frame(minHeight: 220)

            VStack(alignment: .leading, spacing: 0) {
                Text(runtime.terminal.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                RemoteTerminalView(
                    controller: runtime.terminal,
                    isDark: model.isDarkAppearance,
                    settings: model.settings
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.black.opacity(0.92))
            .frame(minHeight: 280)
        }
    }

    @ViewBuilder
    private func idleLayout(runtime: HostRuntime, connecting: Bool) -> some View {
        VStack(spacing: 20) {
            header(runtime: runtime)
            Spacer()
            if connecting {
                ProgressView("Connecting to \(host.username)@\(host.hostname)…")
                    .controlSize(.large)
            } else {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Not connected")
                    .font(.title2.weight(.semibold))
                Text("Metrics and the terminal stay closed until SSH comes up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                if let match = model.sshConfigMatch(for: host), match.username != host.username {
                    Text("~/.ssh/config uses \(match.username)@\(match.hostname) for this Host. This machine is saved as \(host.username).")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                    Button("Use \(match.username) from SSH config") {
                        model.applySSHConfig(to: host)
                    }
                }
                if let error = runtime.lastError, !error.isEmpty {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                Button("Connect") { model.connect(host) }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func header(runtime: HostRuntime) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(host.displayName)
                    .font(.largeTitle.weight(.semibold))
                Text("\(host.username)@\(host.hostname):\(host.port)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Text(runtime.phase.title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
