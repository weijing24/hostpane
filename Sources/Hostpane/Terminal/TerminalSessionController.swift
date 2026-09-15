import AppKit
import HostpaneCore
import SwiftTerm
import Traversio

@MainActor
final class TerminalSessionController: NSObject, @preconcurrency TerminalViewDelegate {
    private(set) var title: String = "Terminal"
    private let terminalView: TerminalView
    private var session: SSHSession?
    private var pendingOutput: [UInt8] = []
    private var lastColumns: UInt32 = 120
    private var lastRows: UInt32 = 36
    private var lastSentColumns: UInt32 = 0
    private var lastSentRows: UInt32 = 0
    private var resizeTask: Task<Void, Never>?
    private var didEnd = false
    private var didBecomeReady = false

    var onReadyToOpenShell: ((UInt32, UInt32) -> Void)?
    var onSessionEnded: (() -> Void)?
    var isBellEnabled: () -> Bool = { true }

    override init() {
        let view = TerminalView(frame: .zero)
        view.wantsLayer = true
        self.terminalView = view
        super.init()
        view.terminalDelegate = self
    }

    func embed(in container: NSView, focus: Bool) {
        if terminalView.superview !== container {
            terminalView.removeFromSuperview()
            for subview in container.subviews {
                subview.removeFromSuperview()
            }
            terminalView.translatesAutoresizingMaskIntoConstraints = true
            terminalView.autoresizingMask = [.width, .height]
            terminalView.frame = container.bounds
            container.addSubview(terminalView)
        }
        if !pendingOutput.isEmpty {
            terminalView.feed(byteArray: pendingOutput[...])
            pendingOutput.removeAll(keepingCapacity: true)
        }
        if focus {
            requestFocus()
        }
    }

    private var appliedDark: Bool?
    private var appliedFontSize: CGFloat?
    private var appliedLineSpacing: CGFloat?
    private var appliedCursorTag: String?
    private var appliedInactive: String?
    private var appliedScrollbar: String?

    func applyPreferences(_ settings: AppSettings) {
        let size = CGFloat(settings.terminalFontSize)
        if appliedFontSize != size {
            appliedFontSize = size
            let font = NSFont(name: "Menlo", size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            terminalView.font = font
        }
        let spacing = CGFloat(settings.terminalLineSpacing)
        if appliedLineSpacing != spacing {
            appliedLineSpacing = spacing
            terminalView.lineSpacing = spacing
        }
        let cursorTag = "\(settings.terminalCursorShape.rawValue)-\(settings.terminalCursorBlink)"
        if appliedCursorTag != cursorTag {
            appliedCursorTag = cursorTag
            terminalView.getTerminal().setCursorStyle(Self.cursorStyle(from: settings))
        }
        if appliedInactive != settings.terminalInactiveCursor.rawValue {
            appliedInactive = settings.terminalInactiveCursor.rawValue
            terminalView.caretViewTracksFocus = settings.terminalInactiveCursor == .fade
        }
        if appliedScrollbar != settings.terminalScrollbar.rawValue {
            appliedScrollbar = settings.terminalScrollbar.rawValue
            applyScrollbar(settings.terminalScrollbar)
        }
    }

    private func applyScrollbar(_ mode: TerminalScrollbar) {
        switch mode {
        case .overlay:
            terminalView.scrollerStyle = .overlay
            setScrollerHidden(false)
        case .always:
            terminalView.scrollerStyle = .legacy
            setScrollerHidden(false)
        case .hidden:
            setScrollerHidden(true)
        }
    }

    private func setScrollerHidden(_ hidden: Bool) {
        terminalView.subviews.compactMap { $0 as? NSScroller }.forEach { $0.isHidden = hidden }
    }

    private static func cursorStyle(from settings: AppSettings) -> CursorStyle {
        switch (settings.terminalCursorShape, settings.terminalCursorBlink) {
        case (.block, true): return .blinkBlock
        case (.block, false): return .steadyBlock
        case (.underline, true): return .blinkUnderline
        case (.underline, false): return .steadyUnderline
        case (.bar, true): return .blinkBar
        case (.bar, false): return .steadyBar
        }
    }

    func applyPalette(isDark: Bool) {
        guard appliedDark != isDark else { return }
        appliedDark = isDark
        let view = terminalView
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        let background: NSColor
        let foreground: NSColor
        if isDark {
            background = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1)
            foreground = NSColor(srgbRed: 0.91, green: 0.91, blue: 0.93, alpha: 1)
        } else {
            background = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            foreground = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        }
        view.nativeBackgroundColor = background
        view.nativeForegroundColor = foreground
        view.setCursorColor(
            source: view.getTerminal(),
            color: SwiftTerm.Color(red8: isDark ? 232 : 28, green8: isDark ? 232 : 28, blue8: isDark ? 234 : 30),
            textColor: SwiftTerm.Color(red8: isDark ? 22 : 255, green8: isDark ? 22 : 255, blue8: isDark ? 24 : 255)
        )
        view.needsDisplay = true
    }

    func bind(session: SSHSession, columns: UInt32, rows: UInt32) {
        self.session = session
        lastColumns = columns
        lastRows = rows
        lastSentColumns = columns
        lastSentRows = rows
        didEnd = false
        requestFocus()
    }

    func unbind() {
        resizeTask?.cancel()
        onReadyToOpenShell = nil
        onSessionEnded = nil
        session = nil
        pendingOutput.removeAll(keepingCapacity: true)
        didBecomeReady = false
        lastSentColumns = 0
        lastSentRows = 0
        terminalView.getTerminal().resetToInitialState()
    }

    func requestFocus() {
        let view = terminalView
        func attempt() {
            view.window?.makeFirstResponder(view)
        }
        attempt()
        DispatchQueue.main.async(execute: attempt)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: attempt)
    }

    func runEventLoop() async {
        guard let session else { return }
        do {
            for try await event in session.events {
                switch event {
                case .standardOutput(let bytes), .standardError(let bytes):
                    feed(bytes)
                case .endOfFile, .exitStatus, .exitSignal:
                    finishSession()
                    return
                @unknown default:
                    break
                }
            }
            finishSession()
        } catch is CancellationError {
            return
        } catch {
            finishSession()
        }
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        let columns = UInt32(max(newCols, 1))
        let rows = UInt32(max(newRows, 1))
        lastColumns = columns
        lastRows = rows
        if !didBecomeReady, newCols >= 20, newRows >= 5 {
            didBecomeReady = true
            onReadyToOpenShell?(columns, rows)
            return
        }
        scheduleResize()
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        self.title = title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard let session, !didEnd else { return }
        let bytes = Array(data)
        Task {
            try? await session.write(bytes)
        }
    }

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    func bell(source: TerminalView) {
        if isBellEnabled() {
            NSSound.beep()
        }
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let text = String(data: content, encoding: .utf8) {
            pasteboard.setString(text, forType: .string)
        }
    }

    func clipboardRead(source: TerminalView) -> Data? {
        NSPasteboard.general.string(forType: .string).flatMap { Data($0.utf8) }
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    private func scheduleResize() {
        guard session != nil, !didEnd else { return }
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.sendResizeIfNeeded()
        }
    }

    private func sendResizeIfNeeded() async {
        guard let session, !didEnd else { return }
        guard lastColumns != lastSentColumns || lastRows != lastSentRows else { return }
        lastSentColumns = lastColumns
        lastSentRows = lastRows
        try? await session.resizePseudoTerminal(
            characterWidth: lastColumns,
            characterHeight: lastRows
        )
    }

    private func finishSession() {
        guard !didEnd else { return }
        didEnd = true
        session = nil
        onSessionEnded?()
    }

    private func feed(_ bytes: [UInt8]) {
        terminalView.feed(byteArray: bytes[...])
    }
}
