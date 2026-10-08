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
        container.onResize = { [weak controller] in
            controller?.containerDidResize()
        }
        controller.applyPalette(isDark: isDark)
        controller.applyPreferences(settings)
        controller.embed(in: container, focus: true)
        return container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        controller.applyPalette(isDark: isDark)
        controller.applyPreferences(settings)
        controller.embed(in: nsView, focus: false)
        nsView.syncTerminalFrame()
    }

    /// Take the column's offer. A large stand-in (the old 800×500) is treated as
    /// a minimum and shoves the sidebar past the window's leading edge.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: TerminalContainerView,
        context: Context
    ) -> CGSize? {
        CGSize(width: Self.offered(proposal.width), height: Self.offered(proposal.height))
    }

    private static func offered(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite, proposed > 1 else { return 10 }
        return proposed
    }
}

final class TerminalContainerView: NSView {
    var onResize: (() -> Void)?
    private var lastSize: NSSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        syncTerminalFrame()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncTerminalFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        lastSize = .zero
        syncTerminalFrame()
    }

    /// On macOS 26 the detail frame runs under the sidebar. The terminal has
    /// to stay in the unobscured rect; otherwise the first columns sit under
    /// the sidebar and the split view shifts that column off the window.
    func syncTerminalFrame() {
        let insets = safeAreaInsets
        let frame = NSRect(
            x: bounds.minX + insets.left,
            y: bounds.minY + insets.bottom,
            width: bounds.width - insets.left - insets.right,
            height: bounds.height - insets.top - insets.bottom
        )
        guard frame.width > 1, frame.height > 1 else { return }
        for subview in subviews where subview.frame != frame {
            subview.frame = frame
        }
        guard lastSize != frame.size else { return }
        lastSize = frame.size
        onResize?()
    }
}
