import SwiftTerm
import SwiftUI

struct TerminalCellView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        TerminalRegistry.shared.getOrCreateView(for: session)
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
    }
}
