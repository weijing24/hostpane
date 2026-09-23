import SwiftUI
import HostpaneCore

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: HostpaneTheme.sidebarWidth,
                    ideal: HostpaneTheme.sidebarWidth,
                    max: 280
                )
        } detail: {
            detail
                .id(model.sidebarSelection)
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.reduceStatusMotion, model.settings.reduceStatusMotion)
        .sheet(item: $model.editor) { _ in
            HostEditorView()
        }
        .sheet(item: $model.keyEditor) { _ in
            KeyEditorView()
        }
        .sheet(item: $model.importDraft) { _ in
            SSHImportView()
        }
        .alert(
            "提示",
            isPresented: Binding(
                get: { model.importMessage != nil },
                set: { if !$0 { model.importMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { model.importMessage = nil }
        } message: {
            Text(model.importMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.sidebarSelection {
        case .dashboard, .none:
            DashboardView()
        case .machines:
            MachinesView()
        case .sshKeys:
            SSHKeysView()
        case .dockerHome:
            DockerRootView()
        case .snippets:
            SnippetsView()
        case .terminalHome:
            TerminalHomeView()
        case .session(let id):
            if let host = model.hosts.first(where: { $0.id == id }) {
                if model.detachedSessionIDs.contains(id) {
                    DetachedSessionPlaceholder(host: host)
                } else {
                    TerminalSessionView(host: host)
                        .id(host.id)
                }
            } else {
                TerminalHomeView()
            }
        case .sftpHome:
            SFTPHomeView()
        case .sftp(let id):
            if let host = model.hosts.first(where: { $0.id == id }) {
                SFTPBrowserView(host: host)
                    .id(host.id)
            } else {
                SFTPHomeView()
            }
        }
    }
}
