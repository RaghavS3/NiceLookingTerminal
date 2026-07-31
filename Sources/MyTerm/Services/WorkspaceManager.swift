import AppKit
import MyTermCore
import Network
import SwiftUI

class WorkspaceManager: ObservableObject {
    static weak var shared: WorkspaceManager?

    enum Mode {
        case terminals
        case planner
    }

    struct AccessCheck: Identifiable {
        let id: String
        let label: String
        let path: String
        let isReadable: Bool
    }

    struct HealthCheck: Identifiable {
        let id: String
        let label: String
        let detail: String
        let isReady: Bool
        let isRequired: Bool
    }

    @Published var mode: Mode = .terminals
    @Published var sessions: [TerminalSession] = [TerminalSession()]
    @Published var activeSessionID: UUID?
    @Published var maximizedSessionID: UUID?
    @Published var showSidebar: Bool = true
    @Published var projectDirectories: [URL] = []
    @Published var projectDiscoveryError: String?
    @Published var closedSessionsHistory: [SavedSession] = []
    @Published var preferences: AppPreferences
    @Published var launchError: String?
    @Published var isShowingSetup = false
    @Published var accessChecks: [AccessCheck] = []
    @Published var isNetworkAvailable = false
    @Published var isOpeningCodexDesktop = false
    @Published var healthChecks: [HealthCheck] = []
    @Published var isCheckingHealth = false
    @Published var transcriptDiskUsage: Int64 = 0
    @Published var attachmentDiskUsage: Int64 = 0
    let plannerStore = PlannerStore()
    private let sessionStore: SessionSettingsStore
    private let attachmentService: AttachmentService
    private let preferencesStore: AppPreferencesStore
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.nicelookingterminal.network-monitor")
    private var codexLaunchProcess: Process?
    private var codexLaunchTimeout: DispatchWorkItem?
    private var sessionSaveWorkItem: DispatchWorkItem?

    var selectedWorkspaceURL: URL {
        if let path = preferences.workspacePath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let desktopProjects = home.appendingPathComponent("Desktop/Projects", isDirectory: true)
        if FileManager.default.fileExists(atPath: desktopProjects.path) {
            return desktopProjects
        }
        let homeProjects = home.appendingPathComponent("Projects", isDirectory: true)
        return FileManager.default.fileExists(atPath: homeProjects.path) ? homeProjects : home
    }

    var isSetupReady: Bool {
        let toolsReady = !healthChecks.isEmpty && healthChecks.allSatisfy { !$0.isRequired || $0.isReady }
        let accessReady =
            preferences.accessMode != .full
            || (!accessChecks.isEmpty && accessChecks.allSatisfy(\.isReadable))
        return toolsReady && accessReady && isNetworkAvailable && preferences.remoteSetupConfirmed
    }

    init(
        sessionStore: SessionSettingsStore = .applicationSupport(),
        attachmentStore: AttachmentPathStore = .applicationSupport(),
        preferencesStore: AppPreferencesStore = .applicationSupport()
    ) {
        let loadedPreferences: AppPreferences
        var preferencesLoadError: Error?
        do {
            loadedPreferences = try preferencesStore.load()
        } catch CocoaError.fileReadNoSuchFile {
            loadedPreferences = AppPreferences()
        } catch {
            loadedPreferences = AppPreferences()
            preferencesLoadError = error
        }

        self.sessionStore = sessionStore
        self.attachmentService = AttachmentService(store: attachmentStore)
        self.preferencesStore = preferencesStore
        self.preferences = loadedPreferences
        let currentIdentity = ApplicationIdentity.current()
        let identityChanged = self.preferences.installationIdentity.map { $0 != currentIdentity.fingerprint } ?? false
        self.isShowingSetup = !self.preferences.onboardingCompleted || identityChanged
        if let preferencesLoadError {
            self.launchError = "Setup preferences were unreadable and have been reset. \(preferencesLoadError.localizedDescription)"
        } else if identityChanged {
            self.launchError = "The app’s signing identity changed. Recheck Full Disk Access and setup health before starting agents."
        }
        WorkspaceManager.shared = self
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        networkMonitor.start(queue: networkQueue)
        refreshProjects()
        refreshHealth()

        if let saved = loadSavedSessions(), !saved.isEmpty {
            var loadedSessions: [TerminalSession] = []
            for item in saved {
                let newSession = TerminalSession(id: item.id)
                newSession.title = item.isAgent ? "\(item.title) — restored shell" : item.title
                newSession.isAgent = false
                newSession.agentPreset = nil
                newSession.customDirectory = item.customDirectory
                loadedSessions.append(newSession)
            }
            self.sessions = loadedSessions
            self.activeSessionID = loadedSessions.first?.id
        } else {
            activeSessionID = sessions.first?.id
        }
    }

    deinit {
        networkMonitor.cancel()
        codexLaunchTimeout?.cancel()
        sessionSaveWorkItem?.cancel()
        codexLaunchProcess?.terminate()
    }

    func refreshProjects() {
        let workspace = selectedWorkspaceURL
        let signpost = PerformanceTelemetry.begin("Project Refresh")
        DispatchQueue.global(qos: .userInitiated).async {
            defer { PerformanceTelemetry.end("Project Refresh", id: signpost) }
            do {
                let projects = try WorkspaceDiscovery.directories(in: workspace)
                DispatchQueue.main.async {
                    self.projectDirectories = projects
                    self.projectDiscoveryError = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.projectDirectories = []
                    self.projectDiscoveryError = error.localizedDescription
                }
            }
        }
    }

    func selectWorkspace(_ directory: URL) {
        preferences.workspacePath = directory.path
        savePreferences()
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Choose your main workspace"
        panel.prompt = "Use Workspace"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = selectedWorkspaceURL

        guard panel.runModal() == .OK, let directory = panel.url else { return }
        selectWorkspace(directory)
        refreshProjects()
        refreshHealth()
    }

    func setAccessMode(_ accessMode: AgentAccessMode) {
        preferences.accessMode = accessMode
        savePreferences()
        refreshHealth()
    }

    func verifyAccess() {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let locations = [
            ("workspace", "Workspace", selectedWorkspaceURL),
            ("downloads", "Downloads", home.appendingPathComponent("Downloads", isDirectory: true)),
            ("documents", "Documents", home.appendingPathComponent("Documents", isDirectory: true)),
            ("desktop", "Desktop", home.appendingPathComponent("Desktop", isDirectory: true)),
        ]

        accessChecks = locations.map { id, label, url in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let canEnumerate =
                (try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsSubdirectoryDescendants]
                )) != nil
            let readable = exists && isDirectory.boolValue && canEnumerate
            return AccessCheck(id: id, label: label, path: url.path, isReadable: readable)
        }
    }

    func refreshHealth() {
        verifyAccess()
        refreshStorageUsage()
        isCheckingHealth = true
        LoginShellEnvironment.shared.resolve { [weak self] (environment: [String]) in
            guard let self else { return }
            var values: [String: String] = [:]
            for entry in environment {
                guard let separator = entry.firstIndex(of: "=") else { continue }
                values[String(entry[..<separator])] = String(entry[entry.index(after: separator)...])
            }
            let pathEntries = values["PATH", default: ""].split(separator: ":").map(String.init)
            let executable: (String) -> String? = { name in
                pathEntries
                    .map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
                    .first { FileManager.default.isExecutableFile(atPath: $0) }
            }
            let codexPath = executable("codex")
            let agyPath = executable("agy")
            let gitPath = executable("git")
            let desktopApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
            let identity = ApplicationIdentity.current()
            self.healthChecks = [
                HealthCheck(
                    id: "shell", label: "Login shell", detail: "/bin/zsh",
                    isReady: FileManager.default.isExecutableFile(atPath: "/bin/zsh"), isRequired: true),
                HealthCheck(
                    id: "codex", label: "Codex CLI", detail: codexPath ?? "Run the supported Codex CLI installer",
                    isReady: codexPath != nil, isRequired: true),
                HealthCheck(
                    id: "desktop", label: "Codex Desktop", detail: desktopApp?.path ?? "Use ‘Open this workspace in Codex’ to install it",
                    isReady: desktopApp != nil, isRequired: true),
                HealthCheck(
                    id: "git", label: "Git", detail: gitPath ?? "Install Apple command-line tools", isReady: gitPath != nil,
                    isRequired: true),
                HealthCheck(
                    id: "agy", label: "AGY", detail: agyPath ?? "Optional — install only if you use AGY", isReady: agyPath != nil,
                    isRequired: false),
                HealthCheck(
                    id: "identity", label: "App identity", detail: identity.detail, isReady: identity.isStableForPrivacyGrants,
                    isRequired: false),
            ]
            self.isCheckingHealth = false
        }
    }

    func openRuntimeStorage() {
        do {
            try FileManager.default.createDirectory(at: MyTermPaths.applicationSupportDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(MyTermPaths.applicationSupportDirectory)
        } catch {
            launchError = "Couldn’t open runtime storage. \(error.localizedDescription)"
        }
    }

    func clearCopiedAttachments() {
        do {
            try AttachmentPathStore.applicationSupport().deleteContents()
            refreshStorageUsage()
        } catch {
            launchError = "Couldn’t delete copied attachments. \(error.localizedDescription)"
        }
    }

    func clearInactiveTranscripts() {
        do {
            try TranscriptStore.applicationSupport().deleteInactiveSessions(
                keeping: Set(sessions.map(\.id))
            )
            refreshStorageUsage()
        } catch {
            launchError = "Couldn’t delete inactive transcripts. \(error.localizedDescription)"
        }
    }

    private func refreshStorageUsage() {
        DispatchQueue.global(qos: .utility).async {
            let transcripts = TranscriptStore.applicationSupport().diskUsage()
            let attachments = AttachmentPathStore.applicationSupport().diskUsage()
            DispatchQueue.main.async {
                self.transcriptDiskUsage = transcripts
                self.attachmentDiskUsage = attachments
            }
        }
    }

    func setRemoteSetupConfirmed(_ confirmed: Bool) {
        preferences.remoteSetupConfirmed = confirmed
        savePreferences()
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func finishSetup() {
        guard isSetupReady else {
            launchError = "Setup is not ready yet. Resolve the highlighted access, tool, network, and Remote checks first."
            return
        }
        preferences.onboardingCompleted = true
        preferences.installationIdentity = ApplicationIdentity.current().fingerprint
        savePreferences()
        isShowingSetup = false
    }

    func runSetupAgain() {
        refreshHealth()
        isShowingSetup = true
    }

    func addSession(in directory: URL? = nil) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            let newSession = TerminalSession()
            if let dir = directory {
                selectWorkspace(dir)
                newSession.customDirectory = dir.path
                newSession.title = dir.lastPathComponent
            }
            sessions.append(newSession)
            activeSessionID = newSession.id
            maximizedSessionID = nil

            _ = TerminalRegistry.shared.getOrCreateView(for: newSession)
            DispatchQueue.main.async {
                TerminalRegistry.shared.focusView(for: newSession.id)
            }
        }
        scheduleSessionStateSave()
    }

    func handleDroppedFiles(_ urls: [URL], onSessionID id: UUID?) {
        let targetID = id ?? activeSessionID
        guard let finalID = targetID else { return }

        // Activate session if dropped on an inactive cell
        if activeSessionID != finalID {
            activeSessionID = finalID
            TerminalRegistry.shared.focusView(for: finalID)
        }

        attachmentService.copyFiles(urls) { result in
            for url in result.insertedURLs {
                TerminalRegistry.shared.sendText(ShellArgumentQuoting.quote(url.path) + " ", to: finalID)
            }
            if !result.failedNames.isEmpty {
                self.launchError =
                    "Some files could not be copied into private storage; their original paths were inserted instead: \(result.failedNames.joined(separator: ", "))"
            }
        }
    }

    func handleDroppedProviders(_ providers: [NSItemProvider], onSessionID id: UUID?) {
        let targetID = id ?? activeSessionID
        guard let finalID = targetID else { return }

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.handleDroppedFiles([url], onSessionID: finalID)
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    if let image = image as? NSImage {
                        self.attachmentService.persistPNG(from: image, prefix: "drop") { result in
                            switch result {
                            case .success(let url):
                                TerminalRegistry.shared.sendText(ShellArgumentQuoting.quote(url.path) + " ", to: finalID)
                            case .failure(let error):
                                self.launchError = "Couldn’t save the image attachment. \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
        }
    }

    @discardableResult
    func handleClipboardImage() -> Bool {
        guard let id = activeSessionID else { return false }
        let pb = NSPasteboard.general

        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            handleDroppedFiles(urls, onSessionID: id)
            return true
        }

        for type in [NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType.tiff] {
            if let data = pb.data(forType: type),
                let image = NSImage(data: data)
            {
                persistClipboardImage(image, for: id)
                return true
            }
        }

        if let image = NSImage(pasteboard: pb) {
            persistClipboardImage(image, for: id)
            return true
        }

        return false
    }

    private func persistClipboardImage(_ image: NSImage, for sessionID: UUID) {
        attachmentService.persistPNG(from: image, prefix: "clip") { result in
            switch result {
            case .success(let url):
                TerminalRegistry.shared.sendText(ShellArgumentQuoting.quote(url.path) + " ", to: sessionID)
            case .failure(let error):
                self.launchError = "Couldn’t save the clipboard image. \(error.localizedDescription)"
            }
        }
    }

    func addSession(for preset: AgentPreset) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            let newSession = TerminalSession()
            newSession.title = preset.title
            newSession.isAgent = true
            newSession.agentPreset = preset.rawValue
            newSession.agentAccessMode = preferences.accessMode
            newSession.customDirectory = selectedWorkspaceURL.path
            sessions.append(newSession)
            activeSessionID = newSession.id
            maximizedSessionID = nil
            _ = TerminalRegistry.shared.getOrCreateView(for: newSession)
            DispatchQueue.main.async {
                TerminalRegistry.shared.focusView(for: newSession.id)
            }
        }
        scheduleSessionStateSave()
    }

    func removeSession(_ session: TerminalSession) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if maximizedSessionID == session.id {
                maximizedSessionID = nil
            }

            let saved = SavedSession(
                id: session.id,
                title: session.title,
                isAgent: session.isAgent,
                agentPreset: session.agentPreset,
                customDirectory: session.customDirectory
            )
            closedSessionsHistory.append(saved)
            if closedSessionsHistory.count > 15 {
                closedSessionsHistory.removeFirst()
            }

            sessions.removeAll { $0.id == session.id }

            TerminalRegistry.shared.removeView(for: session.id)

            if sessions.isEmpty {
                addSession()
            } else if activeSessionID == session.id {
                activeSessionID = sessions.last?.id
            }
        }
        scheduleSessionStateSave()
    }

    func removeActiveSession() {
        if let id = activeSessionID, let session = sessions.first(where: { $0.id == id }) {
            removeSession(session)
        } else if let last = sessions.last {
            removeSession(last)
        }
    }

    func runPreset(_ preset: AgentPreset) {
        mode = .terminals
        addSession(for: preset)
    }

    func openCodexDesktop() {
        guard codexLaunchProcess == nil else { return }
        let workspace = selectedWorkspaceURL
        launchError = nil
        isOpeningCodexDesktop = true
        PerformanceTelemetry.event("Codex Desktop Launch")

        let process = Process()
        let errorPipe = Pipe()
        let errorBuffer = LockedDataBuffer()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-lc",
            "exec codex app \(ShellArgumentQuoting.quote(workspace.path))",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errorBuffer.append(data) }
        }
        process.terminationHandler = { [weak self] finished in
            errorPipe.fileHandleForReading.readabilityHandler = nil
            let tail = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if !tail.isEmpty { errorBuffer.append(tail) }
            let detail = String(decoding: errorBuffer.data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                guard let self, self.codexLaunchProcess === finished else { return }
                self.codexLaunchTimeout?.cancel()
                self.codexLaunchTimeout = nil
                self.codexLaunchProcess = nil
                self.isOpeningCodexDesktop = false
                self.refreshHealth()
                if finished.terminationStatus != 0, self.launchError == nil {
                    let reason = detail.isEmpty ? "Codex could not open the desktop app." : detail
                    self.launchError = "Couldn’t open Codex Desktop for \(workspace.path). \(reason)"
                }
            }
        }

        do {
            try process.run()
            codexLaunchProcess = process
        } catch {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            isOpeningCodexDesktop = false
            launchError = "Couldn’t open Codex Desktop for \(workspace.path). \(error.localizedDescription)"
            return
        }

        let timeout = DispatchWorkItem { [weak self, weak process] in
            guard let self, let process, self.codexLaunchProcess === process, process.isRunning else { return }
            self.launchError = "Opening Codex Desktop timed out. Check the setup health screen and your shell configuration."
            process.terminate()
        }
        codexLaunchTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
    }

    func openRemoteSetup() {
        guard let url = URL(string: "codex://settings/connections/computer") else {
            launchError = "The Codex Desktop Remote settings link is unavailable."
            return
        }
        if !NSWorkspace.shared.open(url) {
            launchError = "Couldn’t open Remote settings. Open Codex Desktop, then choose Settings → Connections."
        }
    }

    func clearActiveInput() {
        guard let id = activeSessionID else { return }
        TerminalRegistry.shared.sendText("\u{15}", to: id)
    }

    func saveSessionState() {
        let signpost = PerformanceTelemetry.begin("Session Save")
        defer { PerformanceTelemetry.end("Session Save", id: signpost) }
        sessionSaveWorkItem?.cancel()
        sessionSaveWorkItem = nil
        let savedList = sessions.map { session in
            SavedSession(
                id: session.id,
                title: session.title,
                isAgent: session.isAgent,
                agentPreset: session.agentPreset,
                customDirectory: session.customDirectory
            )
        }
        do {
            try sessionStore.save(savedList)
        } catch {
            launchError = "Couldn’t save terminal sessions. \(error.localizedDescription)"
        }
    }

    func scheduleSessionStateSave() {
        sessionSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveSessionState()
        }
        sessionSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    func loadSavedSessions() -> [SavedSession]? {
        do {
            return try sessionStore.load()
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            launchError = "Saved terminal sessions were unreadable. \(error.localizedDescription)"
            return nil
        }
    }

    func savePreferences() {
        do {
            try preferencesStore.save(preferences)
        } catch {
            launchError = "Couldn’t save setup preferences. \(error.localizedDescription)"
        }
    }

    func restoreSessions() {
        if !closedSessionsHistory.isEmpty {
            let lastClosed = closedSessionsHistory.removeLast()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                let newSession = TerminalSession(id: lastClosed.id)
                newSession.title = lastClosed.isAgent ? "\(lastClosed.title) — restored shell" : lastClosed.title
                newSession.isAgent = false
                newSession.agentPreset = nil
                newSession.customDirectory = lastClosed.customDirectory

                sessions.append(newSession)
                activeSessionID = newSession.id
                maximizedSessionID = nil

                _ = TerminalRegistry.shared.getOrCreateView(for: newSession)
                DispatchQueue.main.async {
                    TerminalRegistry.shared.focusView(for: newSession.id)
                }
            }
            scheduleSessionStateSave()
            return
        }

        // Otherwise, restore the entire previous session from disk
        guard let saved = loadSavedSessions(), !saved.isEmpty else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            // Clean up existing processes in the registry to avoid leaked terminals
            for session in sessions {
                TerminalRegistry.shared.removeView(for: session.id)
            }
            sessions.removeAll()

            for item in saved {
                let newSession = TerminalSession(id: item.id)
                newSession.title = item.isAgent ? "\(item.title) — restored shell" : item.title
                newSession.isAgent = false
                newSession.agentPreset = nil
                newSession.customDirectory = item.customDirectory

                sessions.append(newSession)
            }

            activeSessionID = sessions.first?.id
            maximizedSessionID = nil

            if let firstID = activeSessionID {
                DispatchQueue.main.async {
                    TerminalRegistry.shared.focusView(for: firstID)
                }
            }
        }
    }
}

private final class LockedDataBuffer {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}
