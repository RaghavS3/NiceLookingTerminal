import AppKit
import Darwin
import MyTermCore
import MyTermTerminal
import SwiftTerm

private enum TerminalConfiguration {
    static let scrollbackLines = 100_000
}

final class LoginShellEnvironment {
    static let shared = LoginShellEnvironment()

    private let queue = DispatchQueue(label: "com.nicelookingterminal.login-environment", qos: .userInitiated)
    private var cachedValues: [String]?
    private var pending: [([String]) -> Void] = []
    private var isResolving = false

    func resolve(_ completion: @escaping ([String]) -> Void) {
        queue.async {
            if let cachedValues = self.cachedValues {
                DispatchQueue.main.async { completion(cachedValues) }
                return
            }

            self.pending.append(completion)
            guard !self.isResolving else { return }
            self.isResolving = true
            let values = self.loadValues()
            self.cachedValues = values
            let callbacks = self.pending
            self.pending.removeAll()
            self.isResolving = false
            DispatchQueue.main.async {
                for callback in callbacks {
                    callback(values)
                }
            }
        }
    }

    private func loadValues() -> [String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "/usr/bin/env -0"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
                if process.isRunning {
                    process.terminate()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let environment = String(decoding: data, as: UTF8.self)
                .split(separator: "\0")
                .map(String.init)
                .filter { $0.contains("=") }
            return environment.isEmpty ? Self.currentEnvironment : environment
        } catch {
            return Self.currentEnvironment
        }
    }

    private static var currentEnvironment: [String] {
        ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
    }
}

final class TerminalRegistry: NSObject, LocalProcessTerminalViewDelegate {
    static let shared = TerminalRegistry()
    private var cache: [UUID: ManagedTerminalView] = [:]
    private var sessionIDsByView: [ObjectIdentifier: UUID] = [:]
    private var sessions: [UUID: TerminalSession] = [:]

    func getOrCreateView(for session: TerminalSession) -> ManagedTerminalView {
        if let existing = cache[session.id] {
            return existing
        }
        let signpost = PerformanceTelemetry.begin("Terminal Creation")
        defer { PerformanceTelemetry.end("Terminal Creation", id: signpost) }
        let terminal = ManagedTerminalView(frame: .zero)
        let id = session.id
        sessions[id] = session
        sessionIDsByView[ObjectIdentifier(terminal)] = id
        terminal.processDelegate = self
        terminal.unseenOutputChanged = { [weak session] hasUnseenOutput in
            session?.hasUnseenOutput = hasUnseenOutput
        }

        let targetPath: String
        if let customDir = session.customDirectory, FileManager.default.fileExists(atPath: customDir) {
            targetPath = customDir
        } else {
            targetPath = WorkspaceManager.shared?.selectedWorkspaceURL.path ?? NSHomeDirectory()
        }

        terminal.changeScrollback(TerminalConfiguration.scrollbackLines)
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .semibold)
        terminal.nativeForegroundColor = NSColor.white
        terminal.nativeBackgroundColor = .clear
        terminal.wantsLayer = true
        terminal.layer?.backgroundColor = NSColor.clear.cgColor
        terminal.layer?.isOpaque = false
        terminal.layer?.drawsAsynchronously = false
        terminal.layer?.cornerRadius = 12
        terminal.layer?.masksToBounds = true
        terminal.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        cache[id] = terminal

        do {
            let transcriptDirectory = try TranscriptStore.applicationSupport().runDirectory(for: id)
            try terminal.configureTranscript(directory: transcriptDirectory, title: session.title) { error in
                WorkspaceManager.shared?.launchError =
                    "Transcript recording stopped because data could not be written. The terminal is still running. \(error.localizedDescription)"
            }
        } catch {
            WorkspaceManager.shared?.launchError =
                "This terminal is running, but its transcript could not be saved. \(error.localizedDescription)"
        }

        if let descriptor = session.launchDescriptor {
            session.processState = .starting
            LoginShellEnvironment.shared.resolve { [weak self, weak terminal, weak session] environment in
                guard let self, let terminal, let session,
                    self.cache[id] === terminal
                else { return }
                terminal.startProcess(
                    executable: "/usr/bin/env",
                    args: [descriptor.executableName] + descriptor.arguments,
                    environment: environment,
                    currentDirectory: targetPath
                )
                session.processState =
                    terminal.process.running
                    ? .running
                    : .failed("Couldn’t start \(descriptor.executableName).")
            }
        } else {
            terminal.startProcess(executable: "/bin/zsh", args: ["-l"], currentDirectory: targetPath)
            session.processState =
                terminal.process.running
                ? .running
                : .failed("Couldn’t start the login shell.")
        }
        return terminal
    }

    func removeView(for id: UUID) {
        if let terminal = cache[id] {
            sessionIDsByView.removeValue(forKey: ObjectIdentifier(terminal))
            terminateProcessTree(for: terminal)
            terminal.closeTranscript()
        }
        cache.removeValue(forKey: id)
        sessions.removeValue(forKey: id)
    }

    func terminateAll() {
        for terminal in cache.values {
            terminateProcessTree(for: terminal)
            terminal.closeTranscript()
        }
        cache.removeAll()
        sessionIDsByView.removeAll()
        sessions.removeAll()
    }

    func sendText(_ text: String, to id: UUID) {
        guard let terminal = cache[id] else { return }
        focusView(for: id)
        terminal.send(txt: text)
    }

    func focusView(for id: UUID) {
        if let terminal = cache[id] {
            DispatchQueue.main.async {
                terminal.window?.makeFirstResponder(terminal)
            }
        }
    }

    func jumpToLatest(for id: UUID) {
        cache[id]?.jumpToLatest()
    }

    func restart(_ session: TerminalSession) {
        removeView(for: session.id)
        session.processState = .starting
        session.hasUnseenOutput = false
        _ = getOrCreateView(for: session)
        focusView(for: session.id)
    }

    func openTranscript(for id: UUID) {
        let store = TranscriptStore.applicationSupport()
        if let transcript = store.latestSearchableTranscript(for: id) {
            NSWorkspace.shared.open(transcript)
        } else if let directory = store.existingSessionDirectory(for: id) {
            NSWorkspace.shared.open(directory)
        } else {
            WorkspaceManager.shared?.launchError = "No transcript has been recorded for this terminal yet."
        }
    }

    func revealTranscript(for id: UUID) {
        guard let directory = TranscriptStore.applicationSupport().existingSessionDirectory(for: id) else {
            WorkspaceManager.shared?.launchError = "No transcript has been recorded for this terminal yet."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func exportTranscript(for id: UUID) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NiceLookingTerminal-\(id.uuidString.prefix(8)).txt"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try TranscriptStore.applicationSupport().exportSession(for: id, to: destination)
        } catch {
            WorkspaceManager.shared?.launchError = "Couldn’t export this transcript. \(error.localizedDescription)"
        }
    }

    func deleteTranscript(for id: UUID) {
        let deleteAndRestartRecording = { [weak self] in
            do {
                let store = TranscriptStore.applicationSupport()
                try store.deleteSession(for: id)
                guard let self, let terminal = self.cache[id], let session = self.sessions[id] else { return }
                let runDirectory = try store.runDirectory(for: id)
                try terminal.configureTranscript(directory: runDirectory, title: session.title) { error in
                    WorkspaceManager.shared?.launchError =
                        "Transcript recording stopped because data could not be written. The terminal is still running. \(error.localizedDescription)"
                }
            } catch {
                WorkspaceManager.shared?.launchError = "Couldn’t delete this transcript. \(error.localizedDescription)"
            }
        }
        if let terminal = cache[id] {
            terminal.closeTranscript(completion: deleteAndRestartRecording)
        } else {
            deleteAndRestartRecording()
        }
    }

    func terminalFirstResponder(in window: NSWindow?) -> ManagedTerminalView? {
        guard let responder = window?.firstResponder else { return nil }
        return cache.values.first { terminal in
            responder === terminal || ((responder as? NSView)?.isDescendant(of: terminal) == true)
        }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let id = sessionIDsByView[ObjectIdentifier(source)], let directory else { return }
        sessions[id]?.customDirectory = directory
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard let id = sessionIDsByView[ObjectIdentifier(source)] else { return }
        guard let session = sessions[id] else { return }
        if exitCode == 127, let executable = session.launchDescriptor?.executableName {
            session.processState = .failed("\(executable) is not installed or could not be found in your login PATH.")
        } else if exitCode == nil {
            session.processState = .disconnected
        } else {
            session.processState = .exited(exitCode)
        }
        (source as? ManagedTerminalView)?.closeTranscript()
    }

    private func terminateProcessTree(for terminal: ManagedTerminalView) {
        let pid = terminal.process.shellPid
        guard pid > 0 else {
            terminal.terminate()
            return
        }

        ProcessTreeTermination.terminateProcessGroup(rootPID: pid)
        terminal.terminate()
    }
}
