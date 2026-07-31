import AppKit
import Darwin
import MyTermCore
import MyTermTerminal
import SwiftTerm
import XCTest

@MainActor
final class PTYIntegrationTests: XCTestCase {
    func testTranscriptRecorderWritesRawAndSearchableFiles() throws {
        let directories = try TemporaryTestDirectories()
        let runDirectory = directories.applicationSupport.appendingPathComponent("run", isDirectory: true)
        let closed = expectation(description: "transcript closes")
        let recorder = try TranscriptRecorder(directory: runDirectory, title: "Test") { error in
            XCTFail("Unexpected transcript failure: \(error)")
        }
        let bytes = Data("hello \u{001B}[31mred\u{001B}[0m 🚀\n".utf8)
        recorder.append(bytes)
        recorder.close { closed.fulfill() }
        wait(for: [closed], timeout: 5)

        XCTAssertEqual(try Data(contentsOf: runDirectory.appendingPathComponent("terminal.raw")), bytes)
        XCTAssertEqual(try Data(contentsOf: runDirectory.appendingPathComponent("transcript.txt")), bytes)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: runDirectory.appendingPathComponent("transcript.txt").path
        )
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testTranscriptCloseIsIdempotent() throws {
        let directories = try TemporaryTestDirectories()
        let runDirectory = directories.applicationSupport.appendingPathComponent("idempotent-close", isDirectory: true)
        let firstClose = expectation(description: "first close")
        let secondClose = expectation(description: "second close")
        let recorder = try TranscriptRecorder(directory: runDirectory, title: "Test") { error in
            XCTFail("Unexpected transcript failure: \(error)")
        }
        recorder.append(Data("complete\n".utf8))
        recorder.close { firstClose.fulfill() }
        recorder.close { secondClose.fulfill() }
        wait(for: [firstClose, secondClose], timeout: 5)

        XCTAssertEqual(
            try String(contentsOf: runDirectory.appendingPathComponent("transcript.txt")),
            "complete\n"
        )
    }

    func testMillionLineTranscriptWritesIncrementally() throws {
        let directories = try TemporaryTestDirectories()
        let runDirectory = directories.applicationSupport.appendingPathComponent("million-line-run", isDirectory: true)
        let closed = expectation(description: "large transcript closes")
        let recorder = try TranscriptRecorder(directory: runDirectory, title: "Large") { error in
            XCTFail("Unexpected transcript failure: \(error)")
        }
        let thousandLines = Data((0..<1_000).map { String(format: "line-%06d\n", $0) }.joined().utf8)
        for _ in 0..<1_000 {
            recorder.append(thousandLines)
        }
        recorder.close { closed.fulfill() }
        wait(for: [closed], timeout: 30)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: runDirectory.appendingPathComponent("terminal.raw").path
        )
        XCTAssertEqual(attributes[.size] as? Int, thousandLines.count * 1_000)
    }

    func testClearedScreenDoesNotRetainColoredDamageBlocks() throws {
        let directories = try TemporaryTestDirectories()
        let view = ManagedTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 360))
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderFront(nil)
        defer {
            if view.process.running { view.terminate() }
            window.orderOut(nil)
        }
        view.nativeBackgroundColor = .black
        view.layer?.drawsAsynchronously = false
        let command =
            "i=1; while [ $i -le 40 ]; do printf '\\033[41m%-80s\\033[0m\\n' RED-DAMAGE; i=$((i+1)); done; sleep 0.2; printf '\\033[2J\\033[Hclean-render\\n'"
        view.startProcess(
            executable: "/bin/zsh",
            args: ["-dfc", command],
            environment: ["TERM=xterm-256color"],
            currentDirectory: directories.attachments.path
        )

        XCTAssertTrue(waitUntil { visibleTerminalText(view.getTerminal()).contains("clean-render") })
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        var staleRedPixels = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.redComponent > 0.45,
                    color.greenComponent < 0.25,
                    color.blueComponent < 0.25
                {
                    staleRedPixels += 1
                }
            }
        }
        XCTAssertEqual(staleRedPixels, 0, "Cleared terminal retained red rendering damage")
    }
    func testProcessGroupTerminationStopsDescendants() throws {
        let directories = try TemporaryTestDirectories()
        let childPIDURL = directories.attachments.appendingPathComponent("child.pid")
        let view = ManagedTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 180))
        view.startProcess(
            executable: "/bin/zsh",
            args: ["-dfc", "sleep 60 & print $! > \(childPIDURL.path); wait"],
            environment: ["TERM=xterm-256color"],
            currentDirectory: directories.attachments.path
        )
        defer { if view.process.running { view.terminate() } }

        XCTAssertTrue(waitUntil { FileManager.default.fileExists(atPath: childPIDURL.path) })
        let childPIDText = try String(contentsOf: childPIDURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let childPID = try XCTUnwrap(pid_t(childPIDText))
        XCTAssertEqual(getpgid(view.process.shellPid), getpgid(childPID))

        XCTAssertNotNil(ProcessTreeTermination.terminateProcessGroup(rootPID: view.process.shellPid, gracePeriod: 0.1))
        view.terminate()
        XCTAssertTrue(waitUntil(timeout: 5) { kill(childPID, 0) != 0 && errno == ESRCH })
    }
    func testNormalBufferAnchorSurvivesAlternateScreenRoundTrip() throws {
        let directories = try TemporaryTestDirectories()
        let view = ManagedTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 180))
        let termination = expectation(description: "alternate-screen producer terminates")
        let processDelegate = PTYProcessDelegate(terminationExpectation: termination)
        view.processDelegate = processDelegate
        var hasUnseenOutput = false
        view.unseenOutputChanged = { hasUnseenOutput = $0 }
        defer { if view.process.running { view.terminate() } }
        view.changeScrollback(1_000)
        let command =
            "i=1; while [ \"$i\" -le 500 ]; do printf 'normal-%04d\\n' \"$i\"; i=$((i+1)); done; sleep 0.5; printf '\\033[?1049h'; printf 'alternate screen\\n'; sleep 0.2; printf '\\033[?1049l'; i=501; while [ \"$i\" -le 520 ]; do printf 'normal-%04d\\n' \"$i\"; i=$((i+1)); done"
        view.startProcess(
            executable: "/bin/zsh",
            args: ["-dfc", command],
            environment: ["TERM=xterm-256color"],
            currentDirectory: directories.attachments.path
        )

        XCTAssertTrue(
            waitUntil {
                visibleTerminalText(view.getTerminal()).contains("normal-0500")
            })
        view.scrollTo(row: 200)
        let anchoredText = visibleTerminalLine(view.getTerminal(), row: 0)
        view.noteUserScrolled()

        wait(for: [termination], timeout: 20)
        XCTAssertTrue(waitUntil { hasUnseenOutput })
        XCTAssertEqual(visibleTerminalLine(view.getTerminal(), row: 0), anchoredText)
    }

    func testManualViewportStaysOnSameContentWhenFullBufferTrims() throws {
        let directories = try TemporaryTestDirectories()
        let view = ManagedTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 180))
        var hasUnseenOutput = false
        view.unseenOutputChanged = { hasUnseenOutput = $0 }
        defer { if view.process.running { view.terminate() } }
        view.changeScrollback(100)
        let command =
            "i=1; while [ \"$i\" -le 200 ]; do printf 'line-%04d\\n' \"$i\"; i=$((i+1)); done; sleep 0.5; i=201; while [ \"$i\" -le 230 ]; do printf 'line-%04d\\n' \"$i\"; i=$((i+1)); done"
        view.startProcess(
            executable: "/bin/zsh",
            args: ["-dfc", command],
            environment: ["TERM=xterm-256color"],
            currentDirectory: directories.attachments.path
        )

        XCTAssertTrue(
            waitUntil {
                visibleTerminalText(view.getTerminal()).contains("line-0200")
            })
        view.scrollTo(row: 75)
        let anchoredText = visibleTerminalLine(view.getTerminal(), row: 0)
        view.noteUserScrolled()

        XCTAssertTrue(waitUntil { hasUnseenOutput })
        XCTAssertEqual(visibleTerminalLine(view.getTerminal(), row: 0), anchoredText)
    }

    func testHundredThousandLineLiveScrollback() throws {
        let directories = try TemporaryTestDirectories()
        let fixture = PTYFixture()
        defer { fixture.terminate() }
        let termination = expectation(description: "100,000-line producer terminates")
        let processDelegate = PTYProcessDelegate(terminationExpectation: termination)
        fixture.view.processDelegate = processDelegate
        fixture.view.changeScrollback(100_100)
        fixture.view.startProcess(
            executable: "/usr/bin/jot",
            args: ["-w", "line-%06d", "100000", "1"],
            environment: ["TERM=xterm-256color"],
            currentDirectory: directories.attachments.path
        )

        wait(for: [termination], timeout: 60)
        XCTAssertEqual(processDelegate.exitCode, 0)
        XCTAssertTrue(
            waitUntil(timeout: 60) {
                visibleTerminalText(fixture.view.getTerminal()).contains("line-100000")
            })

        fixture.view.scroll(toPosition: 0)
        XCTAssertTrue(visibleTerminalLine(fixture.view.getTerminal(), row: 0).contains("line-000001"))
        fixture.view.scroll(toPosition: 1)
        XCTAssertTrue(visibleTerminalText(fixture.view.getTerminal()).contains("line-100000"))
    }

    func testIncomingOutputDoesNotStealManualScrollPosition() throws {
        let directories = try TemporaryTestDirectories()
        let view = ManagedTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 420))
        var hasUnseenOutput = false
        view.unseenOutputChanged = { hasUnseen in
            hasUnseenOutput = hasUnseen
        }
        defer { if view.process.running { view.terminate() } }
        view.changeScrollback(4_000)
        let command =
            "i=1; while [ \"$i\" -le 1000 ]; do printf 'first-%04d\\n' \"$i\"; i=$((i+1)); done; sleep 0.5; i=1; while [ \"$i\" -le 500 ]; do printf 'second-%04d\\n' \"$i\"; i=$((i+1)); done"
        view.startProcess(
            executable: "/bin/zsh",
            args: ["-dfc", command],
            environment: ["TERM=xterm-256color"],
            currentDirectory: directories.attachments.path
        )

        XCTAssertTrue(
            waitUntil {
                view.canScroll && visibleTerminalText(view.getTerminal()).contains("first-1000")
            })

        view.scrollTo(row: 0)
        view.noteUserScrolled()
        let anchoredRow = view.getTerminal().buffer.yDisp
        XCTAssertFalse(view.isFollowingOutput)

        XCTAssertTrue(waitUntil { hasUnseenOutput })
        XCTAssertEqual(view.getTerminal().buffer.yDisp, anchoredRow)

        view.jumpToLatest()
        XCTAssertTrue(view.isFollowingOutput)
        XCTAssertEqual(view.scrollPosition, 1, accuracy: 0.001)
    }

    func testReproduction_PTYThousandsOfLinesScrollAndSelect() throws {
        let directories = try TemporaryTestDirectories()
        let fixture = PTYFixture()
        defer { fixture.terminate() }
        let termination = expectation(description: "PTY producer terminates")
        let processDelegate = PTYProcessDelegate(terminationExpectation: termination)
        fixture.view.processDelegate = processDelegate
        fixture.view.changeScrollback(6_000)

        let command = "i=1; while [ \"$i\" -le 5000 ]; do printf 'line-%04d\\n' \"$i\"; i=$((i+1)); done"
        fixture.view.startProcess(
            executable: "/bin/zsh",
            args: ["-dfc", command],
            environment: ["TERM=xterm-256color"],
            currentDirectory: directories.attachments.path
        )
        wait(for: [termination], timeout: 20)

        XCTAssertEqual(processDelegate.exitCode, 0)
        XCTAssertFalse(fixture.view.process.running)
        let outputDrained = waitUntil(timeout: 20) {
            visibleTerminalText(fixture.view.getTerminal()).contains("line-5000")
        }
        XCTAssertTrue(outputDrained, visibleTerminalText(fixture.view.getTerminal()))

        fixture.view.scroll(toPosition: 0)
        let firstLine = visibleTerminalLine(fixture.view.getTerminal(), row: 0)
        XCTAssertTrue(firstLine.contains("line-0001"), firstLine)

        fixture.view.scroll(toPosition: 1)
        let lastViewport = visibleTerminalText(fixture.view.getTerminal())
        XCTAssertEqual(fixture.view.scrollPosition, 1)
        XCTAssertTrue(lastViewport.contains("line-5000"), lastViewport)

        fixture.view.selectAll()
        let selectedText = try XCTUnwrap(fixture.view.getSelection())
        XCTAssertTrue(selectedText.contains("line-0001"))
        XCTAssertTrue(selectedText.contains("line-5000"))
    }

    func testReproduction_CtrlUErasesRenderedInput() throws {
        let directories = try TemporaryTestDirectories()
        let fixture = PTYFixture()
        defer { fixture.terminate() }
        fixture.view.startProcess(
            executable: "/bin/zsh",
            args: ["-dfi"],
            environment: ["TERM=xterm-256color", "PS1=TEST_PROMPT> "],
            currentDirectory: directories.attachments.path
        )
        let promptAppeared = waitUntil {
            visibleTerminalText(fixture.view.getTerminal()).contains("TEST_PROMPT>")
        }
        XCTAssertTrue(promptAppeared, visibleTerminalText(fixture.view.getTerminal()))

        fixture.view.send(txt: "erased-input")
        let inputAppeared = waitUntil {
            visibleTerminalText(fixture.view.getTerminal()).contains("erased-input")
        }
        XCTAssertTrue(inputAppeared, visibleTerminalText(fixture.view.getTerminal()))

        fixture.view.send(txt: "\u{15}")
        let inputWasErased = waitUntil {
            !visibleTerminalText(fixture.view.getTerminal()).contains("erased-input")
        }
        XCTAssertTrue(inputWasErased, visibleTerminalText(fixture.view.getTerminal()))
    }
}
