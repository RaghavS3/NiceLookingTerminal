import Foundation
import MyTermCore
import XCTest

final class MyTermCoreTests: XCTestCase {
    func testProductIdentityUsesNiceLookingTerminalNaming() {
        XCTAssertEqual(MyTermIdentity.productName, "NiceLookingTerminal")
        XCTAssertEqual(MyTermIdentity.bundleIdentifier, "com.nicelookingterminal.app")
        XCTAssertEqual(MyTermIdentity.repositoryDirectoryName, "NiceLookingTerminal")
    }

    func testSavedSessionSerializationRoundTrips() throws {
        let sessions = [
            SavedSession(
                id: UUID(),
                title: "Build Logs",
                isAgent: false,
                agentPreset: nil,
                customDirectory: "/tmp/Project With Spaces"
            ),
            SavedSession(
                id: UUID(),
                title: "Codex Agent",
                isAgent: true,
                agentPreset: AgentPreset.localCodex.rawValue,
                customDirectory: nil
            ),
        ]

        let data = try JSONEncoder().encode(sessions)
        let decoded = try JSONDecoder().decode([SavedSession].self, from: data)

        XCTAssertEqual(decoded, sessions)
    }

    func testSettingsPersistenceUsesInjectedApplicationSupportDirectory() throws {
        let directories = try TemporaryTestDirectories()
        let fileURL = directories.applicationSupport
            .appendingPathComponent(MyTermIdentity.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("sessions.json")
        let store = SessionSettingsStore(fileURL: fileURL)
        let sessions = [
            SavedSession(
                id: UUID(),
                title: "Temporary Settings",
                isAgent: false,
                agentPreset: nil,
                customDirectory: directories.attachments.path
            )
        ]

        try store.save(sessions)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try store.load(), sessions)
        XCTAssertTrue(fileURL.path.hasPrefix(directories.applicationSupport.path))
    }

    func testWorkspaceDiscoveryPrefersDesktopProjectsAndSkipsFilesAndHiddenDirectories() throws {
        let directories = try TemporaryTestDirectories()
        let desktopProjects = directories.home
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: desktopProjects, withIntermediateDirectories: true)

        try FileManager.default.createDirectory(
            at: desktopProjects.appendingPathComponent("Beta", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: desktopProjects.appendingPathComponent("Alpha", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: desktopProjects.appendingPathComponent(".hidden", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("not a project directory".utf8)
            .write(to: desktopProjects.appendingPathComponent("README.txt"))

        let discovered = WorkspaceDiscovery.projectDirectories(homeDirectory: directories.home)

        XCTAssertEqual(discovered.map(\.lastPathComponent), ["Alpha", "Beta"])
    }

    func testWorkspaceDiscoveryFallsBackToHomeProjects() throws {
        let directories = try TemporaryTestDirectories()
        let homeProjects = directories.home.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: homeProjects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: homeProjects.appendingPathComponent("FallbackProject", isDirectory: true),
            withIntermediateDirectories: true
        )

        let discovered = WorkspaceDiscovery.projectDirectories(homeDirectory: directories.home)

        XCTAssertEqual(discovered.map(\.lastPathComponent), ["FallbackProject"])
    }

    func testWorkspaceDiscoverySurfacesMissingDirectoryErrors() throws {
        let directories = try TemporaryTestDirectories()

        XCTAssertThrowsError(
            try WorkspaceDiscovery.discoverProjectDirectories(homeDirectory: directories.home)
        )
        XCTAssertEqual(WorkspaceDiscovery.projectDirectories(homeDirectory: directories.home), [])
    }

    func testPathQuotingProtectsShellMetacharacters() throws {
        let directories = try TemporaryTestDirectories()
        let path = directories.attachments.appendingPathComponent("screenshot 01.png").path

        XCTAssertEqual(ShellArgumentQuoting.quote(path), "'\(path)'")
        XCTAssertEqual(ShellArgumentQuoting.quote(""), "''")
        XCTAssertEqual(ShellArgumentQuoting.quote("a'b $c `d`\nnext"), "'a'\\''b $c `d`\nnext'")
    }

    func testAttachmentPathsUseTemporaryAttachmentDirectory() throws {
        let directories = try TemporaryTestDirectories()
        let nestedAttachmentDirectory = directories.attachments.appendingPathComponent("nested", isDirectory: true)
        let store = AttachmentPathStore(directoryURL: nestedAttachmentDirectory)

        let generated = try store.uniqueURL(prefix: "clip", fileExtension: "png")
        let named = try store.uniqueURL(
            prefix: "drop",
            originalName: "drop_1234_document.pdf",
            fileExtension: "pdf"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedAttachmentDirectory.path))
        XCTAssertTrue(generated.path.hasPrefix(nestedAttachmentDirectory.path + "/"))
        XCTAssertEqual(named.lastPathComponent, "drop_1234_document.pdf")
    }

    func testAgentLaunchDescriptorsAreCharacterizedWithoutLaunchingAgents() {
        XCTAssertEqual(AgentPreset.localCodex.title, "Local Codex terminal")
        XCTAssertEqual(AgentPreset.localCodex.shortLabel, "AI")
        XCTAssertEqual(
            AgentPreset.localCodex.launchDescriptor(accessMode: .standard),
            AgentLaunchDescriptor(executableName: "codex", arguments: ["--no-alt-screen"])
        )
        XCTAssertEqual(
            AgentPreset.localCodex.launchDescriptor(accessMode: .full),
            AgentLaunchDescriptor(executableName: "codex", arguments: ["--yolo", "--no-alt-screen"])
        )
        XCTAssertEqual(AgentPreset.localCodex.shortcut, "l")
        XCTAssertEqual(AgentPreset.localCodex.symbolName, "circle.hexagongrid.fill")

        XCTAssertEqual(AgentPreset.googleAntigravity.title, "AGY Agent")
        XCTAssertEqual(AgentPreset.googleAntigravity.shortLabel, "G")
        XCTAssertEqual(
            AgentPreset.googleAntigravity.launchDescriptor(accessMode: .full),
            AgentLaunchDescriptor(executableName: "agy", arguments: ["--dangerously-skip-permissions"])
        )
        XCTAssertEqual(AgentPreset.googleAntigravity.shortcut, "g")
        XCTAssertEqual(AgentPreset.googleAntigravity.symbolName, "g.circle.fill")
    }

    func testPreferencesPersistenceRoundTripsAccessChoiceAndWorkspace() throws {
        let directories = try TemporaryTestDirectories()
        let fileURL = directories.applicationSupport.appendingPathComponent("preferences.json")
        let store = AppPreferencesStore(fileURL: fileURL)
        let preferences = AppPreferences(
            workspacePath: directories.home.path,
            accessMode: .full,
            onboardingCompleted: true,
            remoteSetupConfirmed: true
        )

        try store.save(preferences)

        XCTAssertEqual(try store.load(), preferences)
    }

    func testTranscriptDirectoryUsesPrivatePermissions() throws {
        let directories = try TemporaryTestDirectories()
        let store = TranscriptStore(
            directoryURL: directories.applicationSupport.appendingPathComponent("transcripts", isDirectory: true)
        )

        let sessionDirectory = try store.sessionDirectory(for: UUID())
        let attributes = try FileManager.default.attributesOfItem(atPath: sessionDirectory.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)

        XCTAssertEqual(permissions.intValue & 0o777, 0o700)

        let sessionID = UUID()
        let firstRun = try store.runDirectory(for: sessionID)
        let secondRun = try store.runDirectory(for: sessionID)
        XCTAssertNotEqual(firstRun, secondRun)
    }

    func testTranscriptExportPreservesRunsAndCanBeDeleted() throws {
        let directories = try TemporaryTestDirectories()
        let store = TranscriptStore(
            directoryURL: directories.applicationSupport.appendingPathComponent("transcripts", isDirectory: true)
        )
        let sessionID = UUID()
        let firstRun = try store.runDirectory(for: sessionID)
        let secondRun = try store.runDirectory(for: sessionID)
        try Data("first run\n".utf8).write(to: firstRun.appendingPathComponent("transcript.txt"))
        try Data("second run\n".utf8).write(to: secondRun.appendingPathComponent("transcript.txt"))
        let exported = directories.attachments.appendingPathComponent("export.txt")

        try store.exportSession(for: sessionID, to: exported)

        let text = try String(contentsOf: exported)
        XCTAssertTrue(text.contains("first run"))
        XCTAssertTrue(text.contains("second run"))
        XCTAssertGreaterThan(store.diskUsage(), 0)
        XCTAssertNotNil(store.latestSearchableTranscript(for: sessionID))

        try store.deleteSession(for: sessionID)
        XCTAssertNil(store.existingSessionDirectory(for: sessionID))
    }

    func testKanbanTextParserHandlesCommonListFormatsAndUnicode() {
        let text = """
            - [ ] Ship terminal scrolling
            * [x] Fix rendering
            3. Test numbered item
            4) Test alternate numbering
            • Preserve Unicode 🚀

            """

        XCTAssertEqual(
            KanbanTextParser.cardTitles(from: text),
            [
                "Ship terminal scrolling",
                "Fix rendering",
                "Test numbered item",
                "Test alternate numbering",
                "Preserve Unicode 🚀",
            ]
        )
    }

    func testGridLayoutKeepsThirtyPanesReachableAndReadable() {
        let columns = TerminalGridLayout.columnCount(width: 1_400, sessionCount: 30)
        let rows = Int(ceil(Double(30) / Double(columns)))

        XCTAssertEqual(columns, 3)
        XCTAssertEqual(rows, 10)
        XCTAssertEqual(TerminalGridLayout.paneHeight(containerHeight: 900, rows: rows), 320)
        XCTAssertGreaterThanOrEqual(TerminalGridLayout.columnCount(width: 300, sessionCount: 30), 1)
    }
}
