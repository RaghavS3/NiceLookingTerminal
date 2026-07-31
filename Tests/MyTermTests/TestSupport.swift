import AppKit
import Foundation
import SwiftTerm
import XCTest

final class TemporaryTestDirectories {
    let root: URL
    let applicationSupport: URL
    let attachments: URL
    let home: URL

    init() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MyTermTests-\(UUID().uuidString)", isDirectory: true)
        let applicationSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        let attachments = root.appendingPathComponent("attachments", isDirectory: true)
        let home = root.appendingPathComponent("Home", isDirectory: true)

        try fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: attachments, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)

        self.root = root
        self.applicationSupport = applicationSupport
        self.attachments = attachments
        self.home = home
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

final class PTYProcessDelegate: NSObject, LocalProcessTerminalViewDelegate {
    let terminationExpectation: XCTestExpectation
    private(set) var exitCode: Int32?

    init(terminationExpectation: XCTestExpectation) {
        self.terminationExpectation = terminationExpectation
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        self.exitCode = exitCode
        terminationExpectation.fulfill()
    }
}

@MainActor
final class PTYFixture {
    let view: LocalProcessTerminalView

    init(frame: NSRect = NSRect(x: 0, y: 0, width: 800, height: 420)) {
        view = LocalProcessTerminalView(frame: frame)
    }

    func terminate() {
        if view.process.running {
            view.terminate()
        }
    }

}

@MainActor
func visibleTerminalText(_ terminal: Terminal) -> String {
    (0..<terminal.rows).map { row in
        (0..<terminal.cols).map { col in
            String(terminal.getCharacter(col: col, row: row) ?? " ")
        }.joined()
    }.joined(separator: "\n")
}

@MainActor
func visibleTerminalLine(_ terminal: Terminal, row: Int) -> String {
    guard row >= 0, row < terminal.rows else { return "" }
    return (0..<terminal.cols).map { col in
        String(terminal.getCharacter(col: col, row: row) ?? " ")
    }.joined()
}

@MainActor
func waitUntil(
    timeout: TimeInterval = 15,
    condition: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return condition()
}
