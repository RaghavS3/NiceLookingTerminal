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
    private enum SelectionAutoScroll {
        static let interval: TimeInterval = 0.05

        static func step(for locationY: CGFloat, in bounds: CGRect) -> Int {
            if locationY >= bounds.maxY {
                return -velocity(for: locationY - bounds.maxY)
            }
            if locationY <= bounds.minY {
                return velocity(for: bounds.minY - locationY)
            }
            return 0
        }

        private static func velocity(for overflow: CGFloat) -> Int {
            if overflow < 24 {
                return 1
            }
            if overflow < 72 {
                return 3
            }
            return 8
        }
    }

    let terminalView: LocalProcessTerminalView
    var onActivate: () -> Void
    private var dragEventMonitor: Any?
    private var isTrackingTerminalDrag = false
    private var selectionAutoScrollTimer: Timer?
    private var latestSelectionDragEvent: NSEvent?
    private var selectionAutoScrollStep = 0

    init(terminalView: LocalProcessTerminalView, onActivate: @escaping () -> Void) {
        self.terminalView = terminalView
        self.onActivate = onActivate
        super.init(frame: .zero)

        terminalView.removeFromSuperview()
        terminalView.frame = bounds
        terminalView.autoresizingMask = [.width, .height]
        addSubview(terminalView)

        dragEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.observeTerminalDragEvent(event)
            return event
        }
    }

    deinit {
        if let dragEventMonitor {
            NSEvent.removeMonitor(dragEventMonitor)
        }
        selectionAutoScrollTimer?.invalidate()
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
            beginTrackingTerminalDrag()
            activateTerminal()
        }

        return target
    }

    func activateTerminal() {
        onActivate()
        guard window?.firstResponder !== terminalView else { return }
        window?.makeFirstResponder(terminalView)
    }

    static func selectionAutoScrollStep(for locationY: CGFloat, in bounds: CGRect) -> Int {
        SelectionAutoScroll.step(for: locationY, in: bounds)
    }

    private func beginTrackingTerminalDrag() {
        stopSelectionAutoScroll()
        isTrackingTerminalDrag = true
    }

    private func observeTerminalDragEvent(_ event: NSEvent) {
        guard isTrackingTerminalDrag, event.window === window else { return }

        if event.type == .leftMouseUp {
            isTrackingTerminalDrag = false
            stopSelectionAutoScroll()
            return
        }

        guard acceptsSelectionAutoScroll else {
            stopSelectionAutoScroll()
            return
        }

        latestSelectionDragEvent = event
        let location = terminalView.convert(event.locationInWindow, from: nil)
        selectionAutoScrollStep = Self.selectionAutoScrollStep(
            for: location.y,
            in: terminalView.bounds
        )

        if selectionAutoScrollStep == 0 {
            stopSelectionAutoScroll()
        } else {
            startSelectionAutoScrollIfNeeded()
        }
    }

    private var acceptsSelectionAutoScroll: Bool {
        guard terminalView.allowMouseReporting else { return true }
        switch terminalView.terminal.mouseMode {
        case .off:
            return true
        default:
            return false
        }
    }

    private func startSelectionAutoScrollIfNeeded() {
        guard selectionAutoScrollTimer == nil else { return }

        let timer = Timer(timeInterval: SelectionAutoScroll.interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performSelectionAutoScroll()
            }
        }
        selectionAutoScrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func performSelectionAutoScroll() {
        guard
            isTrackingTerminalDrag,
            terminalView.selectionActive,
            acceptsSelectionAutoScroll,
            NSEvent.pressedMouseButtons & 1 == 1,
            let dragEvent = latestSelectionDragEvent,
            selectionAutoScrollStep != 0
        else {
            stopSelectionAutoScroll()
            return
        }

        let previousRow = terminalView.terminal.buffer.yDisp
        if selectionAutoScrollStep < 0 {
            terminalView.scrollUp(lines: -selectionAutoScrollStep)
        } else {
            terminalView.scrollDown(lines: selectionAutoScrollStep)
        }

        guard terminalView.terminal.buffer.yDisp != previousRow else { return }

        // Replaying the latest drag location after the viewport moves makes
        // SwiftTerm extend the selection into each newly revealed row.
        terminalView.mouseDragged(with: dragEvent)
    }

    private func stopSelectionAutoScroll() {
        selectionAutoScrollTimer?.invalidate()
        selectionAutoScrollTimer = nil
        latestSelectionDragEvent = nil
        selectionAutoScrollStep = 0
    }
}
