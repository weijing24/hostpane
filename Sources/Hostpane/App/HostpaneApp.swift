import AppKit
import SwiftUI

@main
struct HostpaneApp: App {
    @State private var model = AppModel()

    init() {
        if let url = Bundle.main.url(forResource: "Hostpane", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(model.settings.appearance.colorScheme)
                .onAppear { model.applyAppearance() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.reloadSyncedDataIfDiskChanged()
                }
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加机器") {
                    model.beginAddHost()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .help) {
                Button("打开应用日志") {
                    model.logger.openInEditor()
                }
                Button("在 Finder 中显示日志") {
                    model.logger.revealInFinder()
                }
            }
        }
        .defaultSize(width: 1200, height: 780)

        WindowGroup(id: "session", for: UUID.self) { $id in
            if let id, let host = model.hosts.first(where: { $0.id == id }) {
                TerminalSessionView(host: host, isDetachedWindow: true)
                    .environment(model)
                    .preferredColorScheme(model.settings.appearance.colorScheme)
                    .frame(minWidth: 720, minHeight: 480)
            } else {
                ContentUnavailableView("会话已关闭", systemImage: "terminal")
                    .frame(minWidth: 480, minHeight: 320)
            }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 640)

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(model.settings.appearance.colorScheme)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 560, height: 640)
    }
}
