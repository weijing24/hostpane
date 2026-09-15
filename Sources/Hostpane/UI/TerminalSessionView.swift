import SwiftUI
import HostpaneCore

struct TerminalHomeView: View {
    var body: some View {
        ContentUnavailableView {
            Label("无会话", systemImage: "terminal")
        } description: {
            Text("在机器卡片上把指针移到机器上，点终端按钮即可连接。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HostpaneTheme.page)
    }
}

struct TerminalSessionView: View {
    @Environment(AppModel.self) private var model
    let host: HostRecord
    var isDetachedWindow = false
    var body: some View {
        @Bindable var model = model
        let runtime = model.runtime(for: host.id)
        NavigationStack {
            ZStack {
                if runtime.progress.cardVisible, runtime.phase != .idle {
                    ConnectionInfoView(host: host)
                } else if runtime.phase == .connected {
                    RemoteTerminalView(
                        controller: runtime.terminal,
                        isDark: model.isDarkAppearance,
                        settings: model.settings
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                } else {
                    HostpaneTheme.page
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(runtime.progress.cardVisible ? HostpaneTheme.page : HostpaneTheme.terminalBackdrop)
            .navigationTitle(host.displayName)
            .navigationSubtitle(statusLine(runtime))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if isDetachedWindow {
                    SessionToolbarItems(host: host, isDetachedWindow: true)
                }
            }
            .inspector(isPresented: $model.sessionInspectorPresented) {
                TerminalInspectorPane(host: host, tab: model.sessionInspectorTab)
                    .inspectorColumnWidth(min: 280, ideal: 340, max: 420)
            }
            .sheet(isPresented: $model.sessionFontSheetPresented) {
                TerminalFontSheet()
            }
            .onAppear {
                if isDetachedWindow {
                    model.detachedSessionIDs.insert(host.id)
                }
            }
            .onDisappear {
                if isDetachedWindow {
                    model.sessionWindowClosed(host.id)
                }
            }
        }
    }

    private func statusLine(_ runtime: HostRuntime) -> String {
        if runtime.progress.cardVisible {
            switch runtime.phase {
            case .connecting: return "终端 · 正在启动 Shell"
            case .connected: return "终端 · 已连接"
            case .failed: return "终端 · 失败"
            case .idle: return "终端"
            }
        }
        switch runtime.phase {
        case .connecting: return "终端 · 连接中"
        case .connected: return "终端 · 运行中"
        case .failed: return "终端 · 失败"
        case .idle: return "终端"
        }
    }
}

struct SessionToolbarItems: ToolbarContent {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let host: HostRecord
    var isDetachedWindow = false

    var body: some ToolbarContent {
        @Bindable var model = model
        let runtime = model.runtime(for: host.id)
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.openSessionInNewWindow(host)
                openWindow(id: "session", value: host.id)
            } label: {
                Label("在新窗口中打开", systemImage: "plus.rectangle.on.rectangle")
            }
            .help("在新窗口中打开")
            .disabled(isDetachedWindow)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Section(sessionStatusLine(runtime)) {
                    Button("强制重启", systemImage: "arrow.clockwise") {
                        model.restartTerminal(host)
                    }
                }
                Button("字体大小和间距", systemImage: "textformat.size") {
                    model.sessionFontSheetPresented = true
                }
                Section("光标和滚动条") {
                    Menu {
                        ForEach(TerminalCursorShape.allCases) { shape in
                            Button(shape.title) {
                                model.settings.terminalCursorShape = shape
                                model.persistSettings()
                            }
                        }
                    } label: {
                        Label("活动光标", systemImage: "character.cursor.ibeam")
                    }
                    Menu {
                        ForEach(TerminalInactiveCursor.allCases) { shape in
                            Button(shape.title) {
                                model.settings.terminalInactiveCursor = shape
                                model.persistSettings()
                            }
                        }
                    } label: {
                        Label("非活动光标", systemImage: "character.cursor.ibeam")
                    }
                    Toggle("光标闪烁", isOn: $model.settings.terminalCursorBlink)
                    Menu {
                        ForEach(TerminalScrollbar.allCases) { mode in
                            Button(mode.title) {
                                model.settings.terminalScrollbar = mode
                                model.persistSettings()
                            }
                        }
                    } label: {
                        Label("滚动条", systemImage: "scroll")
                    }
                }
                Toggle("终端提示音", isOn: $model.settings.terminalBellEnabled)
                Divider()
                Picker("显示", selection: $model.settings.sessionToolbarMode) {
                    ForEach(SessionToolbarMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button("关闭会话", systemImage: "xmark.circle") {
                    model.disconnect(host)
                }
            } label: {
                Label("操作", systemImage: "ellipsis")
            }
            .help("操作")
            .menuIndicator(.visible)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.sessionInspectorPresented.toggle()
            } label: {
                Label("检查器", systemImage: "sidebar.trailing")
            }
            .help("检查器")
        }
        if model.sessionInspectorPresented {
            ToolbarItem(placement: .primaryAction) {
                Picker("检查器", selection: $model.sessionInspectorTab) {
                    Text("代码片段").tag(TerminalInspectorTab.snippets)
                    Text("状态").tag(TerminalInspectorTab.status)
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 168)
            }
        }
    }
}

@MainActor
private func sessionStatusLine(_ runtime: HostRuntime) -> String {
    if runtime.progress.cardVisible {
        switch runtime.phase {
        case .connecting: return "终端 · 正在启动 Shell"
        case .connected: return "终端 · 已连接"
        case .failed: return "终端 · 失败"
        case .idle: return "终端"
        }
    }
    switch runtime.phase {
    case .connecting: return "终端 · 连接中"
    case .connected: return "终端 · 运行中"
    case .failed: return "终端 · 失败"
    case .idle: return "终端"
    }
}

enum TerminalInspectorTab: String, CaseIterable, Identifiable {
    case snippets
    case status

    var id: String { rawValue }
}

private struct TerminalInspectorPane: View {
    let host: HostRecord
    var tab: TerminalInspectorTab

    var body: some View {
        Group {
            switch tab {
            case .snippets:
                TerminalSnippetsPane()
            case .status:
                HostInspectView(host: host, showsChrome: false)
            }
        }
        .background(HostpaneTheme.page)
    }
}

private struct TerminalSnippetsPane: View {
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("搜索代码片段或软件包", text: $query)
                .textFieldStyle(.roundedBorder)
            Text("包")
                .font(.headline)
            ContentUnavailableView {
                Label("无可用代码片段包", systemImage: "shippingbox")
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            Text("代码片段")
                .font(.headline)
            ContentUnavailableView {
                Label("无可用代码片段", systemImage: "curlybraces")
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

private struct TerminalFontSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Slider(value: $model.settings.terminalFontSize, in: 9...22, step: 1) {
                    Text("字体大小：\(Int(model.settings.terminalFontSize.rounded()))")
                }
                Slider(value: $model.settings.terminalLineSpacing, in: 1.0...1.6, step: 0.05) {
                    Text(String(format: "行距：%.0f%%", model.settings.terminalLineSpacing * 100))
                }
            }
            .formStyle(.grouped)
            .navigationTitle("字体大小和间距")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: model.settings) { _, _ in
                model.persistSettings()
            }
        }
        .frame(width: 420, height: 240)
    }
}

struct DetachedSessionPlaceholder: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let host: HostRecord

    var body: some View {
        ContentUnavailableView {
            Label("会话在独立窗口中", systemImage: "macwindow")
        } description: {
            Text("\(host.displayName) 的终端已经在另一个窗口打开。")
        } actions: {
            Button("显示窗口") {
                openWindow(id: "session", value: host.id)
            }
            Button("在主窗口打开") {
                model.openTerminal(host)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HostpaneTheme.page)
        .navigationTitle(host.displayName)
    }
}
