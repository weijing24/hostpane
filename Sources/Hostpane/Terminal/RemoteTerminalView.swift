import AppKit
import HostpaneCore
import SwiftTerm
import SwiftUI

struct RemoteTerminalView: NSViewRepresentable {
    var controller: TerminalSessionController
    var isDark: Bool
    var settings: AppSettings

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView(frame: .zero)
        controller.applyPalette(isDark: isDark)
        controller.applyPreferences(settings)
        controller.embed(in: container, focus: true)
        return container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        controller.applyPalette(isDark: isDark)
        controller.applyPreferences(settings)
        controller.embed(in: nsView, focus: false)
    }
}

final class TerminalContainerView: NSView {
    override func layout() {
        super.layout()
        subviews.forEach { $0.frame = bounds }
    }
}
