import AppKit
import SwiftTerm
import SwiftUI

struct TerminalCellView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    let onActivate: () -> Void

    func makeNSView(context: Context) -> TerminalHostView {
        TerminalHostView(
            terminalView: TerminalRegistry.shared.getOrCreateView(for: session),
            onActivate: onActivate
        )
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        nsView.onActivate = onActivate
    }
}

@MainActor
final class TerminalHostView: NSView {
    let terminalView: LocalProcessTerminalView
    var onActivate: () -> Void

    init(terminalView: LocalProcessTerminalView, onActivate: @escaping () -> Void) {
        self.terminalView = terminalView
        self.onActivate = onActivate
        super.init(frame: .zero)

        terminalView.removeFromSuperview()
        terminalView.frame = bounds
        terminalView.autoresizingMask = [.width, .height]
        addSubview(terminalView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let target = super.hitTest(point)
        let hitsTerminal =
            target === terminalView
            || target?.isDescendant(of: terminalView) == true

        if hitsTerminal, NSApp.currentEvent?.type == .leftMouseDown {
            activateTerminal()
        }

        return target
    }

    func activateTerminal() {
        onActivate()
        guard window?.firstResponder !== terminalView else { return }
        window?.makeFirstResponder(terminalView)
    }
}
