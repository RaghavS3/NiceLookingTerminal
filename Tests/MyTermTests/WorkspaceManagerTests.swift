import Foundation
import MyTermCore
import XCTest

@testable import MyTermApp

@MainActor
final class WorkspaceManagerTests: XCTestCase {
    func testThirtySavedSessionsRestoreLazilyWithStableIDs() throws {
        let directories = try TemporaryTestDirectories()
        let sessionURL = directories.applicationSupport.appendingPathComponent("sessions.json")
        let preferencesURL = directories.applicationSupport.appendingPathComponent("preferences.json")
        let sessions = (0..<30).map { index in
            SavedSession(
                id: UUID(),
                title: "Terminal \(index)",
                isAgent: false,
                agentPreset: nil,
                customDirectory: directories.home.path
            )
        }
        try SessionSettingsStore(fileURL: sessionURL).save(sessions)
        try AppPreferencesStore(fileURL: preferencesURL).save(
            AppPreferences(workspacePath: directories.home.path)
        )

        let manager = WorkspaceManager(
            sessionStore: SessionSettingsStore(fileURL: sessionURL),
            attachmentStore: AttachmentPathStore(directoryURL: directories.attachments),
            preferencesStore: AppPreferencesStore(fileURL: preferencesURL)
        )

        XCTAssertEqual(manager.sessions.map(\.id), sessions.map(\.id))
        XCTAssertTrue(manager.sessions.allSatisfy { $0.processState == .starting })
        TerminalRegistry.shared.terminateAll()
    }

    func testSetupReadinessRequiresEveryRequiredGate() throws {
        let directories = try TemporaryTestDirectories()
        let manager = WorkspaceManager(
            sessionStore: SessionSettingsStore(fileURL: directories.applicationSupport.appendingPathComponent("sessions.json")),
            attachmentStore: AttachmentPathStore(directoryURL: directories.attachments),
            preferencesStore: AppPreferencesStore(fileURL: directories.applicationSupport.appendingPathComponent("preferences.json"))
        )
        manager.isNetworkAvailable = true
        manager.healthChecks = [
            .init(id: "required", label: "Required", detail: "ready", isReady: true, isRequired: true),
            .init(id: "optional", label: "Optional", detail: "missing", isReady: false, isRequired: false),
        ]
        manager.preferences.accessMode = .standard
        XCTAssertTrue(manager.isSetupReady)

        manager.healthChecks[0] = .init(id: "required", label: "Required", detail: "missing", isReady: false, isRequired: true)
        XCTAssertFalse(manager.isSetupReady)
        TerminalRegistry.shared.terminateAll()
    }

    func testOptionalDesktopAndRemoteDoNotBlockSetup() throws {
        let directories = try TemporaryTestDirectories()
        let manager = WorkspaceManager(
            sessionStore: SessionSettingsStore(fileURL: directories.applicationSupport.appendingPathComponent("sessions.json")),
            attachmentStore: AttachmentPathStore(directoryURL: directories.attachments),
            preferencesStore: AppPreferencesStore(fileURL: directories.applicationSupport.appendingPathComponent("preferences.json"))
        )
        manager.preferences.remoteSetupConfirmed = false
        manager.isNetworkAvailable = true
        manager.healthChecks = [
            .init(id: "codex", label: "Codex CLI", detail: "ready", isReady: true, isRequired: true),
            .init(id: "desktop", label: "Codex Desktop", detail: "optional", isReady: false, isRequired: false),
        ]
        manager.preferences.accessMode = .standard

        XCTAssertTrue(manager.isSetupReady)
        TerminalRegistry.shared.terminateAll()
    }

    func testChangedSigningIdentityReopensSetup() throws {
        let directories = try TemporaryTestDirectories()
        let preferencesURL = directories.applicationSupport.appendingPathComponent("preferences.json")
        try AppPreferencesStore(fileURL: preferencesURL).save(
            AppPreferences(
                workspacePath: directories.home.path,
                onboardingCompleted: true,
                remoteSetupConfirmed: true,
                installationIdentity: "different-signing-identity"
            )
        )

        let manager = WorkspaceManager(
            sessionStore: SessionSettingsStore(fileURL: directories.applicationSupport.appendingPathComponent("sessions.json")),
            attachmentStore: AttachmentPathStore(directoryURL: directories.attachments),
            preferencesStore: AppPreferencesStore(fileURL: preferencesURL)
        )

        XCTAssertTrue(manager.isShowingSetup)
        XCTAssertNil(manager.launchError)
        TerminalRegistry.shared.terminateAll()
    }

    func testFullAccessCodexSessionUsesYoloWithoutLaunchingAnAgent() throws {
        let directories = try TemporaryTestDirectories()
        let manager = WorkspaceManager(
            sessionStore: SessionSettingsStore(fileURL: directories.applicationSupport.appendingPathComponent("sessions.json")),
            attachmentStore: AttachmentPathStore(directoryURL: directories.attachments),
            preferencesStore: AppPreferencesStore(fileURL: directories.applicationSupport.appendingPathComponent("preferences.json"))
        )

        let session = manager.makeAgentSession(for: .localCodex, accessMode: .full)

        XCTAssertEqual(session.title, AgentPreset.localCodex.title)
        XCTAssertEqual(session.customDirectory, manager.selectedWorkspaceURL.path)
        XCTAssertEqual(
            session.launchDescriptor,
            AgentLaunchDescriptor(executableName: "codex", arguments: ["--yolo", "--no-alt-screen"])
        )
        TerminalRegistry.shared.terminateAll()
    }
}
