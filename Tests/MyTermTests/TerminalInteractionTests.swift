import AppKit
import SwiftTerm
import XCTest

@testable import MyTermApp

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
}
