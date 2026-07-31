import Darwin
import Foundation

public enum AgentPreset: String, CaseIterable {
    case localCodex
    case googleAntigravity

    public var title: String {
        switch self {
        case .localCodex: return "Local Codex terminal"
        case .googleAntigravity: return "AGY Agent"
        }
    }

    public var shortLabel: String {
        switch self {
        case .localCodex: return "AI"
        case .googleAntigravity: return "G"
        }
    }

    public func launchDescriptor(accessMode: AgentAccessMode) -> AgentLaunchDescriptor {
        switch self {
        case .localCodex:
            var arguments = ["--no-alt-screen"]
            if accessMode == .full {
                arguments.insert("--yolo", at: 0)
            }
            return AgentLaunchDescriptor(executableName: "codex", arguments: arguments)
        case .googleAntigravity:
            let arguments = accessMode == .full ? ["--dangerously-skip-permissions"] : []
            return AgentLaunchDescriptor(executableName: "agy", arguments: arguments)
        }
    }

    public var shortcut: String {
        switch self {
        case .localCodex: return "l"
        case .googleAntigravity: return "g"
        }
    }

    public var symbolName: String {
        switch self {
        case .localCodex: return "circle.hexagongrid.fill"
        case .googleAntigravity: return "g.circle.fill"
        }
    }
}

public enum AgentAccessMode: String, Codable, CaseIterable {
    case standard
    case full
}

public struct AgentLaunchDescriptor: Equatable {
    public let executableName: String
    public let arguments: [String]

    public init(executableName: String, arguments: [String]) {
        self.executableName = executableName
        self.arguments = arguments
    }
}

public struct AppPreferences: Codable, Equatable {
    public var workspacePath: String?
    public var accessMode: AgentAccessMode
    public var onboardingCompleted: Bool
    public var remoteSetupConfirmed: Bool
    public var installationIdentity: String?

    public init(
        workspacePath: String? = nil,
        accessMode: AgentAccessMode = .standard,
        onboardingCompleted: Bool = false,
        remoteSetupConfirmed: Bool = false,
        installationIdentity: String? = nil
    ) {
        self.workspacePath = workspacePath
        self.accessMode = accessMode
        self.onboardingCompleted = onboardingCompleted
        self.remoteSetupConfirmed = remoteSetupConfirmed
        self.installationIdentity = installationIdentity
    }
}

public struct AppPreferencesStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupport() -> Self {
        Self(fileURL: MyTermPaths.applicationSupportDirectory.appendingPathComponent("preferences.json"))
    }

    public func save(_ preferences: AppPreferences) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(preferences).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func load() throws -> AppPreferences {
        try JSONDecoder().decode(AppPreferences.self, from: Data(contentsOf: fileURL))
    }
}

public enum MyTermPaths {
    public static var applicationSupportDirectory: URL {
        let root =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return root.appendingPathComponent(MyTermIdentity.bundleIdentifier, isDirectory: true)
    }
}

public struct SavedSession: Codable, Equatable {
    public let id: UUID
    public let title: String
    public let isAgent: Bool
    public let agentPreset: String?
    public let customDirectory: String?

    public init(id: UUID, title: String, isAgent: Bool, agentPreset: String?, customDirectory: String?) {
        self.id = id
        self.title = title
        self.isAgent = isAgent
        self.agentPreset = agentPreset
        self.customDirectory = customDirectory
    }
}

public struct SessionSettingsStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupport() -> Self {
        Self(fileURL: MyTermPaths.applicationSupportDirectory.appendingPathComponent("sessions.json"))
    }

    public func save(_ sessions: [SavedSession]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(sessions)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func load() throws -> [SavedSession] {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([SavedSession].self, from: data)
    }
}

public enum WorkspaceDiscovery {
    public static func discoverProjectDirectories(
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let desktopProjects =
            homeDirectory
            .appendingPathComponent("Desktop")
            .appendingPathComponent("Projects")
        let homeProjects = homeDirectory.appendingPathComponent("Projects")
        let target = fileManager.fileExists(atPath: desktopProjects.path) ? desktopProjects : homeProjects

        return try directories(in: target, fileManager: fileManager)
    }

    public static func directories(
        in workspace: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: workspace,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return
            contents
            .filter { url in
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }

    public static func projectDirectories(homeDirectory: URL, fileManager: FileManager = .default) -> [URL] {
        (try? discoverProjectDirectories(homeDirectory: homeDirectory, fileManager: fileManager)) ?? []
    }
}

public struct AttachmentPathStore {
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public static func applicationSupport() -> Self {
        Self(directoryURL: MyTermPaths.applicationSupportDirectory.appendingPathComponent("attachments", isDirectory: true))
    }

    @discardableResult
    public func ensureDirectory(fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        return directoryURL
    }

    public func uniqueURL(
        prefix: String,
        originalName: String? = nil,
        fileExtension: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = try ensureDirectory(fileManager: fileManager)
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let suffix = UUID().uuidString.prefix(8)
        let filename: String
        if let originalName, !originalName.isEmpty {
            filename = originalName
        } else {
            filename = "\(prefix)_\(timestamp)_\(suffix).\(fileExtension)"
        }
        return directory.appendingPathComponent(filename)
    }

    public func diskUsage(fileManager: FileManager = .default) -> Int64 {
        directoryDiskUsage(directoryURL, fileManager: fileManager)
    }

    public func deleteContents(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        for url in try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: url)
        }
    }
}

public struct TranscriptStore {
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public static func applicationSupport() -> Self {
        Self(directoryURL: MyTermPaths.applicationSupportDirectory.appendingPathComponent("transcripts", isDirectory: true))
    }

    public func sessionDirectory(for sessionID: UUID, fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        let directory = directoryURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        return directory
    }

    public func runDirectory(
        for sessionID: UUID,
        runID: UUID = UUID(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let sessionDirectory = try sessionDirectory(for: sessionID, fileManager: fileManager)
        let runDirectory = sessionDirectory.appendingPathComponent(runID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runDirectory.path)
        return runDirectory
    }

    public func existingSessionDirectory(for sessionID: UUID, fileManager: FileManager = .default) -> URL? {
        let directory = directoryURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return directory
    }

    public func deleteSession(for sessionID: UUID, fileManager: FileManager = .default) throws {
        guard let directory = existingSessionDirectory(for: sessionID, fileManager: fileManager) else { return }
        try fileManager.removeItem(at: directory)
    }

    public func latestSearchableTranscript(for sessionID: UUID, fileManager: FileManager = .default) -> URL? {
        guard let sessionDirectory = existingSessionDirectory(for: sessionID, fileManager: fileManager),
            let enumerator = fileManager.enumerator(
                at: sessionDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else { return nil }

        return enumerator.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == "transcript.txt" }
            .max {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }
    }

    public func diskUsage(fileManager: FileManager = .default) -> Int64 {
        directoryDiskUsage(directoryURL, fileManager: fileManager)
    }

    public func deleteInactiveSessions(
        keeping activeSessionIDs: Set<UUID>,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        for url in try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey]) {
            guard let sessionID = UUID(uuidString: url.lastPathComponent),
                !activeSessionIDs.contains(sessionID)
            else { continue }
            try fileManager.removeItem(at: url)
        }
    }

    public func exportSession(
        for sessionID: UUID,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        guard let sessionDirectory = existingSessionDirectory(for: sessionID, fileManager: fileManager) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let runs = try fileManager.contentsOfDirectory(
            at: sessionDirectory,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted {
            let left = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return left < right
        }

        fileManager.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        for run in runs {
            let textURL = run.appendingPathComponent("transcript.txt")
            guard fileManager.fileExists(atPath: textURL.path) else { continue }
            try output.write(contentsOf: Data("\n===== Run \(run.lastPathComponent) =====\n".utf8))
            try output.write(contentsOf: Data(contentsOf: textURL))
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}

private func directoryDiskUsage(_ directoryURL: URL, fileManager: FileManager) -> Int64 {
    guard
        let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
    else { return 0 }

    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
            values.isRegularFile == true
        else { continue }
        total += Int64(values.fileSize ?? 0)
    }
    return total
}

public enum ShellArgumentQuoting {
    public static func quote(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public enum ProcessTreeTermination {
    @discardableResult
    public static func terminateProcessGroup(rootPID: pid_t, gracePeriod: TimeInterval = 2) -> pid_t? {
        guard rootPID > 0 else { return nil }
        let processGroup = getpgid(rootPID)
        guard processGroup > 0, processGroup != getpgrp() else { return nil }

        kill(-processGroup, SIGTERM)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + gracePeriod) {
            if kill(-processGroup, 0) == 0 || errno == EPERM {
                kill(-processGroup, SIGKILL)
            }
        }
        return processGroup
    }
}

public enum KanbanTextParser {
    public static func cardTitles(from text: String) -> [String] {
        let prefixPattern = #"^\s*(?:(?:[-*+•‣◦]\s*)?(?:\[[ xX]\])\s*|[-*+•‣◦]\s+|\d+[.)]\s+)"#
        let prefixRegex = try? NSRegularExpression(pattern: prefixPattern)

        return text.components(separatedBy: .newlines).compactMap { line in
            var title = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            if let prefixRegex {
                let range = NSRange(title.startIndex..<title.endIndex, in: title)
                title = prefixRegex.stringByReplacingMatches(
                    in: title,
                    range: range,
                    withTemplate: ""
                )
            }

            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
    }
}

public enum TerminalGridLayout {
    public static func columnCount(width: CGFloat, sessionCount: Int) -> Int {
        let safeSessionCount = max(1, sessionCount)
        let fittingCount = max(1, Int((width - 28 + 12) / (380 + 12)))
        let preferredCount = safeSessionCount <= 1 ? 1 : safeSessionCount <= 4 ? 2 : 3
        return min(safeSessionCount, min(preferredCount, fittingCount))
    }

    public static func paneHeight(containerHeight: CGFloat, rows: Int) -> CGFloat {
        let availableHeight = containerHeight - 30
        let fittedHeight = (availableHeight - CGFloat(max(0, rows - 1)) * 12) / CGFloat(max(1, rows))
        return rows <= 2 ? max(300, fittedHeight) : 320
    }
}
