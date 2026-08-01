import AppKit
import SwiftTerm
import XCTest

@testable import MyTermApp
@testable import MyTermTerminal

@MainActor
final class TerminalInteractionTests: XCTestCase {
    func testActivationFocusesTheTerminalAndUpdatesPaneStateTogether() {
        let terminal = LocalProcessTerminalView(frame: .zero)
        var activationCount = 0
        let host = TerminalHostView(terminalView: terminal) {
            activationCount += 1
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host

        host.activateTerminal()

        XCTAssertEqual(activationCount, 1)
        XCTAssertTrue(window.firstResponder === terminal)
    }

    func testHostKeepsTheCachedTerminalSizedToItsPane() {
        let terminal = LocalProcessTerminalView(frame: .zero)
        let host = TerminalHostView(terminalView: terminal, onActivate: {})
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(terminal.frame, host.bounds)
    }

    func testSelectionDragAutoScrollsTowardContentBeyondTheViewport() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 360)

        XCTAssertEqual(
            TerminalHostView.selectionAutoScrollStep(for: bounds.maxY, in: bounds),
            -1
        )
        XCTAssertEqual(
            TerminalHostView.selectionAutoScrollStep(for: bounds.maxY + 40, in: bounds),
            -3
        )
        XCTAssertEqual(
            TerminalHostView.selectionAutoScrollStep(for: bounds.maxY + 100, in: bounds),
            -8
        )
        XCTAssertEqual(
            TerminalHostView.selectionAutoScrollStep(for: bounds.minY, in: bounds),
            1
        )
        XCTAssertEqual(
            TerminalHostView.selectionAutoScrollStep(for: bounds.midY, in: bounds),
            0
        )
    }

    func testTerminalIsExposedAsAFocusedEditableTextArea() {
        let terminal = ManagedTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let window = NSWindow(
            contentRect: terminal.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = terminal

        XCTAssertTrue(terminal.isAccessibilityElement())
        XCTAssertEqual(terminal.accessibilityRole(), .textArea)
        XCTAssertEqual(terminal.accessibilityLabel(), "Terminal input")
        XCTAssertEqual(terminal.accessibilityPlaceholderValue(), "Type a command")

        terminal.setAccessibilityFocused(true)

        XCTAssertTrue(terminal.isAccessibilityFocused())
        XCTAssertTrue(window.firstResponder === terminal)
    }
}
