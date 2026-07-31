import SwiftUI
import AppKit
import SwiftTerm

typealias Color = SwiftUI.Color

// MARK: - Core Session & Drawing Models

class TerminalSession: Identifiable, ObservableObject, Equatable {
    let id = UUID()
    @Published var title: String = "Shell"
    @Published var isAgent: Bool = false
    @Published var customDirectory: String? = nil
    @Published var agentPreset: String? = nil

    static func == (lhs: TerminalSession, rhs: TerminalSession) -> Bool {
        lhs.id == rhs.id
    }
}

enum AgentPreset: String, CaseIterable {
    case openAICodex
    case googleAntigravity

    var title: String {
        switch self {
        case .openAICodex: return "Codex Agent"
        case .googleAntigravity: return "AGY Agent"
        }
    }

    var shortLabel: String {
        switch self {
        case .openAICodex: return "AI"
        case .googleAntigravity: return "G"
        }
    }

    var command: String {
        switch self {
        case .openAICodex: return "codex --yolo"
        case .googleAntigravity: return "agy --dangerously-skip-permissions"
        }
    }

    var shortcut: String {
        switch self {
        case .openAICodex: return "o"
        case .googleAntigravity: return "g"
        }
    }

    var symbolName: String {
        switch self {
        case .openAICodex: return "circle.hexagongrid.fill"
        case .googleAntigravity: return "g.circle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .openAICodex: return Color(red: 1.0, green: 0.84, blue: 0.0) // Premium Codex Yellow
        case .googleAntigravity: return .blue
        }
    }
}

struct SavedSession: Codable {
    let title: String
    let isAgent: Bool
    let agentPreset: String?
    let customDirectory: String?
}

enum DrawingTool: String, CaseIterable {
    case select = "arrow"
    case pen = "pencil"
    case rect = "square"
    case circle = "circle"
    case text = "textformat"
    case eraser = "eraser"
}

enum FillStyle {
    case empty
    case hachure
    case solid
}

enum StrokePattern {
    case solid
    case dashed
}

struct DrawingShape: Identifiable {
    let id = UUID()
    var tool: DrawingTool
    var points: [CGPoint] = []
    var rect: CGRect = .zero
    var text: String = ""
    var color: Color = .black
    var lineWidth: CGFloat = 3
    var fillStyle: FillStyle = .empty
    var strokeStyle: StrokePattern = .solid
    var fontSize: CGFloat = 18

    // Performance: Store deterministic sketchy paths once to avoid CPU spikes during render
    var sketchyPath: Path? = nil
    var hachurePath: Path? = nil

    // Bounds tracking for selection & dragging
    var bounds: CGRect {
        switch tool {
        case .rect, .circle:
            return rect
        case .text:
            // Estimate a bounding box for text rendering based on font size!
            let countFactor = CGFloat(text.count)
            let sizeFactor = fontSize * 0.55
            let width = (countFactor * sizeFactor) + 20.0
            let height = fontSize + 12.0
            if let p = points.first {
                return CGRect(x: p.x, y: p.y - 4, width: width, height: height)
            }
            return .zero
        case .pen:
            if points.isEmpty { return .zero }
            let xs = points.map { $0.x }
            let ys = points.map { $0.y }
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 0
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        default:
            return .zero
        }
    }
}

func CGPointDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    return sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
}

class WorkspaceManager: ObservableObject {
    static var shared: WorkspaceManager? = nil

    enum Mode {
        case terminals
        case planner
    }

    @Published var mode: Mode = .terminals
    @Published var sessions: [TerminalSession] = [TerminalSession()]
    @Published var activeSessionID: UUID?
    @Published var maximizedSessionID: UUID?
    @Published var showSidebar: Bool = true
    @Published var projectDirectories: [URL] = []
    @Published var closedSessionsHistory: [SavedSession] = []

    init() {
        WorkspaceManager.shared = self
        refreshProjects()

        // Auto-restore previous sessions if they exist
        if let saved = loadSavedSessions(), !saved.isEmpty {
            var loadedSessions: [TerminalSession] = []
            for item in saved {
                let newSession = TerminalSession()
                newSession.title = item.title
                newSession.isAgent = item.isAgent
                newSession.agentPreset = item.agentPreset
                newSession.customDirectory = item.customDirectory
                loadedSessions.append(newSession)
            }
            self.sessions = loadedSessions
            self.activeSessionID = loadedSessions.first?.id

            // For any agent sessions, trigger their command send after a short delay
            for session in loadedSessions {
                if session.isAgent, let presetRaw = session.agentPreset, let preset = AgentPreset(rawValue: presetRaw) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        TerminalRegistry.shared.focusView(for: session.id)
                        TerminalRegistry.shared.sendText(preset.command + "\r", to: session.id)
                    }
                }
            }
        } else {
            activeSessionID = sessions.first?.id
        }
    }

    func refreshProjects() {
        let desktopProjectsPath = NSHomeDirectory() + "/Desktop/Projects"
        let homeProjectsPath = NSHomeDirectory() + "/Projects"
        let targetPath = FileManager.default.fileExists(atPath: desktopProjectsPath) ? desktopProjectsPath : homeProjectsPath

        let url = URL(fileURLWithPath: targetPath)
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            self.projectDirectories = contents.filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
        } catch {
            self.projectDirectories = []
        }
    }

    func addSession(in directory: URL? = nil) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            let newSession = TerminalSession()
            if let dir = directory {
                newSession.customDirectory = dir.path
                newSession.title = dir.lastPathComponent
            }
            sessions.append(newSession)
            activeSessionID = newSession.id
            maximizedSessionID = nil

            // Focus the new terminal immediately for zero-click typing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                TerminalRegistry.shared.focusView(for: newSession.id)
            }
        }
        saveSessionState()
    }

    private var attachmentDirectoryURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop")
            .appendingPathComponent("Projects")
            .appendingPathComponent("NiceLookingTerminal")
            .appendingPathComponent("attachments")
    }

    private func ensureAttachmentDirectory() throws -> URL {
        let directory = attachmentDirectoryURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func uniqueAttachmentURL(prefix: String, originalName: String? = nil, fileExtension: String) throws -> URL {
        let directory = try ensureAttachmentDirectory()
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let suffix = UUID().uuidString.prefix(8)
        let filename = originalName?.isEmpty == false ? originalName! : "\(prefix)_\(timestamp)_\(suffix).\(fileExtension)"
        return directory.appendingPathComponent(filename)
    }

    private func writeImageAttachment(_ image: NSImage, prefix: String) -> URL? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            let url = try uniqueAttachmentURL(prefix: prefix, fileExtension: "png")
            try pngData.write(to: url, options: .atomic)
            return url
        } catch {
            NSSound.beep()
            return nil
        }
    }

    // Intelligent File & Image Handling
    func handleDroppedFiles(_ urls: [URL], onSessionID id: UUID?) {
        let targetID = id ?? activeSessionID
        guard let finalID = targetID else { return }

        // Activate session if dropped on an inactive cell
        if activeSessionID != finalID {
            activeSessionID = finalID
            TerminalRegistry.shared.focusView(for: finalID)
        }

        for url in urls {
            do {
                let ext = url.pathExtension.isEmpty ? "file" : url.pathExtension
                let timestamp = Int(Date().timeIntervalSince1970 * 1000)
                let suffix = UUID().uuidString.prefix(8)
                let filename = "drop_\(timestamp)_\(suffix)_\(url.lastPathComponent)"
                let destination = try uniqueAttachmentURL(prefix: "drop", originalName: filename, fileExtension: ext)
                try FileManager.default.copyItem(at: url, to: destination)
                TerminalRegistry.shared.sendText("\"\(destination.path)\" ", to: finalID)
            } catch {
                TerminalRegistry.shared.sendText("\"\(url.path)\" ", to: finalID)
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
                        DispatchQueue.main.async {
                            if let url = self.writeImageAttachment(image, prefix: "drop") {
                                TerminalRegistry.shared.sendText("\"\(url.path)\" ", to: finalID)
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
               let image = NSImage(data: data),
               let url = writeImageAttachment(image, prefix: "clip") {
                TerminalRegistry.shared.sendText("\"\(url.path)\" ", to: id)
                return true
            }
        }

        if let image = NSImage(pasteboard: pb), let url = writeImageAttachment(image, prefix: "clip") {
            TerminalRegistry.shared.sendText("\"\(url.path)\" ", to: id)
            return true
        }

        return false
    }

    func addSession(for preset: AgentPreset) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            let newSession = TerminalSession()
            newSession.title = preset.title
            newSession.isAgent = true
            newSession.agentPreset = preset.rawValue
            sessions.append(newSession)
            activeSessionID = newSession.id
            maximizedSessionID = nil

            // Focus and send command immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                TerminalRegistry.shared.focusView(for: newSession.id)
                TerminalRegistry.shared.sendText(preset.command + "\r", to: newSession.id)
            }
        }
        saveSessionState()
    }

    func removeSession(_ session: TerminalSession) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if maximizedSessionID == session.id {
                maximizedSessionID = nil
            }

            // Save to closed sessions history for Cmd+Shift+T reopen!
            let saved = SavedSession(
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

            // Critical Lifecycle Cleanup: Terminate process and remove from registry cache
            TerminalRegistry.shared.removeView(for: session.id)

            if sessions.isEmpty {
                addSession()
            } else if activeSessionID == session.id {
                activeSessionID = sessions.last?.id
            }
        }
        saveSessionState()
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

    func clearActiveAgentChat() {
        guard let id = activeSessionID, let session = sessions.first(where: { $0.id == id }) else { return }
        if session.isAgent {
            // Agent-specific clear sequence: Ctrl+U (clear line) + /clear
            TerminalRegistry.shared.sendText("\u{15}/clear\r", to: id)
        } else {
            // Plain terminal: just erase current input line (Standard macOS Cmd+Backspace behavior!)
            TerminalRegistry.shared.sendText("\u{15}", to: id)
        }
    }

    private var savedSessionsFilePath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("com.nicelookingterminal.MyTerm")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("sessions.json")
    }

    func saveSessionState() {
        let savedList = sessions.map { session in
            SavedSession(
                title: session.title,
                isAgent: session.isAgent,
                agentPreset: session.agentPreset,
                customDirectory: session.customDirectory
            )
        }
        do {
            let data = try JSONEncoder().encode(savedList)
            try data.write(to: savedSessionsFilePath, options: .atomic)
        } catch {
            print("Failed to save sessions: \(error)")
        }
    }

    func loadSavedSessions() -> [SavedSession]? {
        do {
            let data = try Data(contentsOf: savedSessionsFilePath)
            return try JSONDecoder().decode([SavedSession].self, from: data)
        } catch {
            return nil
        }
    }

    func restoreSessions() {
        if !closedSessionsHistory.isEmpty {
            // Reopen the last closed tab!
            let lastClosed = closedSessionsHistory.removeLast()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                let newSession = TerminalSession()
                newSession.title = lastClosed.title
                newSession.isAgent = lastClosed.isAgent
                newSession.agentPreset = lastClosed.agentPreset
                newSession.customDirectory = lastClosed.customDirectory

                sessions.append(newSession)
                activeSessionID = newSession.id
                maximizedSessionID = nil

                if lastClosed.isAgent, let presetRaw = lastClosed.agentPreset, let preset = AgentPreset(rawValue: presetRaw) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        TerminalRegistry.shared.focusView(for: newSession.id)
                        TerminalRegistry.shared.sendText(preset.command + "\r", to: newSession.id)
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        TerminalRegistry.shared.focusView(for: newSession.id)
                    }
                }
            }
            saveSessionState()
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
                let newSession = TerminalSession()
                newSession.title = item.title
                newSession.isAgent = item.isAgent
                newSession.agentPreset = item.agentPreset
                newSession.customDirectory = item.customDirectory

                sessions.append(newSession)

                // If it is an agent, we want to launch the preset command after zsh boots up
                if item.isAgent, let presetRaw = item.agentPreset, let preset = AgentPreset(rawValue: presetRaw) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        TerminalRegistry.shared.focusView(for: newSession.id)
                        TerminalRegistry.shared.sendText(preset.command + "\r", to: newSession.id)
                    }
                }
            }

            activeSessionID = sessions.first?.id
            maximizedSessionID = nil

            if let firstID = activeSessionID {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    TerminalRegistry.shared.focusView(for: firstID)
                }
            }
        }
    }
}

// MARK: - SwiftTerm Wrapper

func hideScrollBars(in view: NSView) {
    if let scrollView = view as? NSScrollView {
        // Do NOT set hasVerticalScroller or hasHorizontalScroller to false
        // as doing so disables drag-autoscrolling (highlighting and scrolling).
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.isHidden = true
        scrollView.horizontalScroller?.isHidden = true
        scrollView.verticalScroller?.alphaValue = 0.0
        scrollView.horizontalScroller?.alphaValue = 0.0
        scrollView.verticalScroller?.frame = .zero
        scrollView.horizontalScroller?.frame = .zero
    }
    if let scroller = view as? NSScroller {
        scroller.isHidden = true
        scroller.alphaValue = 0.0
        scroller.frame = .zero
    }
    for subview in view.subviews {
        hideScrollBars(in: subview)
    }
}

class TerminalRegistry {
    static let shared = TerminalRegistry()
    private var cache: [UUID: LocalProcessTerminalView] = [:]

    func getOrCreateView(for id: UUID, customDirectory: String? = nil) -> LocalProcessTerminalView {
        if let existing = cache[id] {
            return existing
        }
        let terminal = LocalProcessTerminalView(frame: .zero)

        // Determine the target startup directory (custom directory or standard fallback)
        let targetPath: String
        if let customDir = customDirectory, FileManager.default.fileExists(atPath: customDir) {
            targetPath = customDir
        } else {
            let desktopProjectsPath = NSHomeDirectory() + "/Desktop/Projects"
            let homeProjectsPath = NSHomeDirectory() + "/Projects"
            if FileManager.default.fileExists(atPath: desktopProjectsPath) {
                targetPath = desktopProjectsPath
            } else if FileManager.default.fileExists(atPath: homeProjectsPath) {
                targetPath = homeProjectsPath
            } else {
                targetPath = NSHomeDirectory()
            }
        }

        // Start process in the specific target directory using per-session currentDirectory
        terminal.startProcess(executable: "/bin/zsh", args: ["-l"], currentDirectory: targetPath)

        terminal.font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .semibold)
        terminal.nativeForegroundColor = NSColor.white

        // Use a clear background to enable a premium, unified frosted glass aesthetic
        terminal.nativeBackgroundColor = .clear

        // Optimize layer backing for buttery-smooth character rendering and crisp Retina displays
        terminal.wantsLayer = true
        terminal.layer?.backgroundColor = NSColor.clear.cgColor
        terminal.layer?.isOpaque = false
        terminal.layer?.drawsAsynchronously = true
        terminal.layer?.cornerRadius = 12
        terminal.layer?.masksToBounds = true
        terminal.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Remove native SwiftTerm vertical and horizontal scrollbars recursively
        hideScrollBars(in: terminal)

        cache[id] = terminal
        return terminal
    }

    func removeView(for id: UUID) {
        if let terminal = cache[id] {
            terminal.terminate()
        }
        cache.removeValue(forKey: id)
    }

    func sendText(_ text: String, to id: UUID) {
        let terminal = getOrCreateView(for: id)
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
}

struct TerminalCellView: NSViewRepresentable {
    let sessionID: UUID
    let customDirectory: String?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        return TerminalRegistry.shared.getOrCreateView(for: sessionID, customDirectory: customDirectory)
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // No recursive logic here to prevent typing lag!
    }
}

// MARK: - Aesthetic Terminal Grid Cell

struct GridCell: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject var manager: WorkspaceManager
    @State private var isHovered = false
    @State private var showTitleEditor = false
    @State private var tempTitle = ""

    var isActive: Bool { manager.activeSessionID == session.id }
    var isMaximized: Bool { manager.maximizedSessionID == session.id }

    var body: some View {
        ZStack {
            // Flush terminal layout spanning 100% of cell
            TerminalCellView(sessionID: session.id, customDirectory: session.customDirectory)
                .padding(8)

            inactiveOverlay

            hoverControls

            titleEditor
        }
        .background(cellBackground)
        .overlay(cellStrokeOverlayActive)
        .overlay(cellStrokeOverlayInactive)
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            manager.handleDroppedProviders(providers, onSessionID: session.id)
            return true
        }
        // Performance: Reduced shadow complexity to prevent compositor lag in multi-pane grids
        .shadow(color: isActive ? Color.white.opacity(0.02) : Color.clear, radius: 4, x: 0, y: 1)
        .cornerRadius(18)
        .onHover { hovering in
            // Fast hover response without spring bounce
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var inactiveOverlay: some View {
        ZStack {
            if !isActive {
                // Dimming layer that allows clicks to pass through if it's already active or for selection
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            manager.activeSessionID = session.id
                            TerminalRegistry.shared.focusView(for: session.id)
                        }
                    }

                if !session.title.isEmpty {
                    Text(session.title.uppercased())
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.15))
                        .allowsHitTesting(false)
                } else {
                    Text("SHELL")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.15))
                        .allowsHitTesting(false)
                }
            }
        }
        .allowsHitTesting(!isActive) // If active, the entire ZStack doesn't intercept hits
    }

    @ViewBuilder
    private var hoverControls: some View {
        VStack {
            HStack {
                Spacer()
                if isHovered {
                    HStack(spacing: 8) {
                        if !session.title.isEmpty {
                            Text(session.title.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(4)
                        }

                        HStack(spacing: 6) {
                            Button(action: {
                                tempTitle = session.title
                                showTitleEditor = true
                            }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    if isMaximized {
                                        manager.maximizedSessionID = nil
                                    } else {
                                        manager.maximizedSessionID = session.id
                                        manager.activeSessionID = session.id
                                    }
                                }
                            }) {
                                Image(systemName: isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                manager.removeSession(session)
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(4)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .transition(.opacity)
                }
            }
            .padding(10)
            Spacer()
        }
    }

    @ViewBuilder
    private var titleEditor: some View {
        if showTitleEditor {
            ZStack {
                Color.black.opacity(0.4)
                    .onTapGesture { showTitleEditor = false }

                VStack(spacing: 12) {
                    Text("Terminal Title")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))

                    TextField("e.g. Server, Logs...", text: $tempTitle, onCommit: {
                        session.title = tempTitle
                        showTitleEditor = false
                        WorkspaceManager.shared?.saveSessionState()
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))

                    HStack {
                        Button("Cancel") { showTitleEditor = false }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))

                        Spacer()

                        Button("Save") {
                            session.title = tempTitle
                            showTitleEditor = false
                            WorkspaceManager.shared?.saveSessionState()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.blue)
                    }
                }
                .padding(14)
                .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .frame(width: 200)
            }
        }
    }

    @ViewBuilder
    private var cellBackground: some View {
        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            .cornerRadius(18)
            .opacity(isActive ? 0.4 : 0.2)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isActive ? Color.white.opacity(0.03) : Color.white.opacity(0.01))
            )
    }

    @ViewBuilder
    private var cellStrokeOverlayActive: some View {
        RoundedRectangle(cornerRadius: 18)
            .stroke(
                LinearGradient(colors: [Color.white.opacity(isActive ? 0.35 : 0.0), Color.white.opacity(isActive ? 0.12 : 0.0)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: isActive ? 1.5 : 0
            )
    }

    @ViewBuilder
    private var cellStrokeOverlayInactive: some View {
        RoundedRectangle(cornerRadius: 18)
            .stroke(Color.white.opacity(isActive ? 0.0 : 0.05), lineWidth: 1)
    }
}

// MARK: - Dynamic Grid System with Alive-State Management

struct DynamicGridView: View {
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        let count = manager.sessions.count
        let cols = count <= 1 ? 1 : count == 2 ? 2 : count <= 4 ? 2 : 3
        let rows = Int(ceil(Double(count) / Double(cols)))

        let _ = manager.maximizedSessionID != nil

        ZStack {
            if let maxID = manager.maximizedSessionID, let maxSession = manager.sessions.first(where: { $0.id == maxID }) {
                // High-performance single maximized cell bypass
                GridCell(session: maxSession, manager: manager)
                    .id(maxSession.id)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .padding(.top, 8)
            } else {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    if count == 3 {
                        GridRow {
                            GridCell(session: manager.sessions[0], manager: manager)
                                .id(manager.sessions[0].id)
                            GridCell(session: manager.sessions[1], manager: manager)
                                .id(manager.sessions[1].id)
                        }
                        GridRow {
                            GridCell(session: manager.sessions[2], manager: manager)
                                .id(manager.sessions[2].id)
                                .gridCellColumns(2)
                        }
                    } else if count == 5 {
                        GridRow {
                            GridCell(session: manager.sessions[0], manager: manager)
                                .id(manager.sessions[0].id)
                                .gridCellColumns(2)
                            GridCell(session: manager.sessions[1], manager: manager)
                                .id(manager.sessions[1].id)
                                .gridCellColumns(2)
                            GridCell(session: manager.sessions[2], manager: manager)
                                .id(manager.sessions[2].id)
                                .gridCellColumns(2)
                        }
                        GridRow {
                            GridCell(session: manager.sessions[3], manager: manager)
                                .id(manager.sessions[3].id)
                                .gridCellColumns(3)
                            GridCell(session: manager.sessions[4], manager: manager)
                                .id(manager.sessions[4].id)
                                .gridCellColumns(3)
                        }
                    } else {
                        ForEach(0..<rows, id: \.self) { row in
                            GridRow {
                                ForEach(0..<cols, id: \.self) { col in
                                    let index = row * cols + col
                                    if index < count {
                                        let session = manager.sessions[index]
                                        GridCell(session: session, manager: manager)
                                            .id(session.id)
                                    } else {
                                        Color.clear
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Excalidraw Sketchy Geometry Engine

func sketchyLine(from start: CGPoint, to end: CGPoint, roughness: CGFloat = 1.2) -> Path {
    var path = Path()
    let length = CGPointDistance(start, end)
    if length < 1 { return path }

    for _ in 0..<2 {
        let offset1 = CGFloat.random(in: -roughness...roughness)
        let offset2 = CGFloat.random(in: -roughness...roughness)
        let offset3 = CGFloat.random(in: -roughness...roughness)
        let offset4 = CGFloat.random(in: -roughness...roughness)

        let p1 = CGPoint(x: start.x + offset1, y: start.y + offset2)
        let p2 = CGPoint(x: end.x + offset3, y: end.y + offset4)

        let mid = CGPoint(
            x: (p1.x + p2.x)/2 + CGFloat.random(in: -roughness...roughness),
            y: (p1.y + p2.y)/2 + CGFloat.random(in: -roughness...roughness)
        )

        path.move(to: p1)
        path.addQuadCurve(to: p2, control: mid)
    }
    return path
}

func sketchyRect(rect: CGRect, roughness: CGFloat = 1.2) -> Path {
    var path = Path()
    let tl = rect.origin
    let tr = CGPoint(x: rect.maxX, y: rect.minY)
    let br = CGPoint(x: rect.maxX, y: rect.maxY)
    let bl = CGPoint(x: rect.minX, y: rect.maxY)

    path.addPath(sketchyLine(from: tl, to: tr, roughness: roughness))
    path.addPath(sketchyLine(from: tr, to: br, roughness: roughness))
    path.addPath(sketchyLine(from: br, to: bl, roughness: roughness))
    path.addPath(sketchyLine(from: bl, to: tl, roughness: roughness))

    return path
}

func sketchyCircle(rect: CGRect, roughness: CGFloat = 1.2) -> Path {
    var path = Path()
    let cx = rect.midX
    let cy = rect.midY
    let rx = rect.width / 2
    let ry = rect.height / 2

    for _ in 0..<2 {
        let segments = 16
        var points: [CGPoint] = []
        for i in 0...segments {
            let angle = (CGFloat(i) / CGFloat(segments)) * CGFloat.pi * 2
            let rOffsetFactor = CGFloat.random(in: -roughness...roughness)
            let curRx = rx + rOffsetFactor
            let curRy = ry + rOffsetFactor
            let px = cx + cos(angle) * curRx
            let py = cy + sin(angle) * curRy
            points.append(CGPoint(x: px, y: py))
        }
        if points.count > 1 {
            path.move(to: points[0])
            for k in 1..<points.count {
                path.addLine(to: points[k])
            }
        }
    }
    return path
}

func sketchyHachure(rect: CGRect, spacing: CGFloat = 10, roughness: CGFloat = 1.0) -> Path {
    var path = Path()
    let width = rect.width
    let height = rect.height
    if width < 5 || height < 5 { return path }

    let startX = rect.minX
    let startY = rect.minY

    var offset: CGFloat = 0
    while offset < (width + height) {
        let x1 = max(startX, startX + offset - height)
        let y1 = min(rect.maxY, startY + offset)
        let x2 = min(rect.maxX, startX + offset)
        let y2 = max(startY, startY + offset - width)

        if x1 != x2 && y1 != y2 {
            path.addPath(sketchyLine(from: CGPoint(x: x1, y: y1), to: CGPoint(x: x2, y: y2), roughness: roughness))
        }
        offset += spacing
    }
    return path
}

// MARK: - Whiteboard Settings Floating Panel Controls

struct WidthOption: View {
    let width: CGFloat
    let label: String
    let current: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(current == width ? .white : .white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(current == width ? Color.white.opacity(0.15) : Color.white.opacity(0.03))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(current == width ? 0.2 : 0.05), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct StyleOption: View {
    let icon: String
    let style: StrokePattern
    let current: StrokePattern
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(current == style ? .white : .white.opacity(0.6))
                .frame(width: 28, height: 28)
                .background(current == style ? Color.white.opacity(0.15) : Color.white.opacity(0.03))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(current == style ? 0.2 : 0.05), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct FillOption: View {
    let icon: String
    let style: FillStyle
    let current: FillStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(current == style ? .white : .white.opacity(0.6))
                .frame(width: 28, height: 28)
                .background(current == style ? Color.white.opacity(0.15) : Color.white.opacity(0.03))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(current == style ? 0.2 : 0.05), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct FontSizeOption: View {
    let size: CGFloat
    let label: String
    let current: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(current == size ? .white : .white.opacity(0.5))
                .frame(width: 32, height: 26)
                .background(current == size ? Color.blue.opacity(0.85) : Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(current == size ? 0.15 : 0.04), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct WhiteboardSettingsSidebar: View {
    @Binding var strokeWidth: CGFloat
    @Binding var strokeStyle: StrokePattern
    @Binding var fillStyle: FillStyle
    @Binding var fontSize: CGFloat
    @State private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PROPERTIES")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isCollapsed.toggle()
                    }
                }) {
                    Image(systemName: isCollapsed ? "chevron.right.circle.fill" : "chevron.left.circle.fill")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 14) {
                    // Stroke Width
                    VStack(alignment: .leading, spacing: 5) {
                        Text("STROKE WIDTH")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 6) {
                            WidthOption(width: 2, label: "Thin", current: strokeWidth) { strokeWidth = 2 }
                            WidthOption(width: 4, label: "Medium", current: strokeWidth) { strokeWidth = 4 }
                            WidthOption(width: 7, label: "Thick", current: strokeWidth) { strokeWidth = 7 }
                        }
                    }

                    // Stroke Style
                    VStack(alignment: .leading, spacing: 5) {
                        Text("STROKE STYLE")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 6) {
                            StyleOption(icon: "line.3.horizontal", style: .solid, current: strokeStyle) { strokeStyle = .solid }
                            StyleOption(icon: "line.dashed", style: .dashed, current: strokeStyle) { strokeStyle = .dashed }
                        }
                    }

                    // Fill Style
                    VStack(alignment: .leading, spacing: 5) {
                        Text("FILL STYLE")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 6) {
                            FillOption(icon: "circle", style: .empty, current: fillStyle) { fillStyle = .empty }
                            FillOption(icon: "circle.dashed", style: .hachure, current: fillStyle) { fillStyle = .hachure }
                            FillOption(icon: "circle.fill", style: .solid, current: fillStyle) { fillStyle = .solid }
                        }
                    }

                    // Font Size Options
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TEXT SIZE")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 6) {
                            FontSizeOption(size: 14, label: "S", current: fontSize) { fontSize = 14 }
                            FontSizeOption(size: 18, label: "M", current: fontSize) { fontSize = 18 }
                            FontSizeOption(size: 24, label: "L", current: fontSize) { fontSize = 24 }
                            FontSizeOption(size: 36, label: "XL", current: fontSize) { fontSize = 36 }
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(14)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .frame(width: isCollapsed ? 120 : 200)
    }
}

// MARK: - Whiteboard Gray Dotted Background Pattern

func generateDotTileImage() -> NSImage {
    let size = NSSize(width: 24, height: 24)
    let image = NSImage(size: size)
    image.lockFocus()

    let dotRect = NSRect(x: 11, y: 11, width: 2, height: 2)
    NSColor.gray.withAlphaComponent(0.35).set()
    let path = NSBezierPath(ovalIn: dotRect)
    path.fill()

    image.unlockFocus()
    return image
}

struct DotGridView: View {
    var body: some View {
        Color.clear
            .background(
                Image(nsImage: generateDotTileImage())
                    .resizable(resizingMode: .tile)
            )
    }
}

// MARK: - Whiteboard Tool Buttons

struct ToolButton: View {
    let icon: String
    let tool: DrawingTool
    let activeTool: DrawingTool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: activeTool == tool ? "\(icon).fill" : icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(activeTool == tool ? .white : .white.opacity(0.6))
                .frame(width: 32, height: 32)
                .background(activeTool == tool ? Color.blue.opacity(0.8) : Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(activeTool == tool ? 0.2 : 0.05), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ColorDot: View {
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: selected ? 2 : 0)
                )
                .scaleEffect(selected ? 1.25 : 1.0)
                .shadow(color: Color.black.opacity(0.2), radius: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Complete Excalidraw Whiteboard View (Infinite Overlay-Driven)

struct WhiteboardView: View {
    @State private var shapes: [DrawingShape] = []
    @State private var currentShape: DrawingShape?
    @State private var activeTool: DrawingTool = .select
    @State private var strokeColor: Color = .black
    @State private var strokeWidth: CGFloat = 4
    @State private var strokeStyle: StrokePattern = .solid
    @State private var fillStyle: FillStyle = .hachure
    @State private var fontSize: CGFloat = 18

    // Interactive Selection & Dragging States
    @State private var selectedShapeID: UUID? = nil
    @State private var isDraggingShape = false
    @State private var dragStartPoint: CGPoint = .zero
    @State private var shapeOriginalPoints: [CGPoint] = []
    @State private var shapeOriginalRect: CGRect = .zero

    // Text Spawning & Double-Click Editor Setup
    @State private var showTextInput = false
    @State private var textInputVal = ""
    @State private var textSpawnPoint: CGPoint = .zero

    func shouldEraseShape(_ shape: DrawingShape, at point: CGPoint) -> Bool {
        if shape.tool == .rect || shape.tool == .circle {
            return shape.rect.insetBy(dx: -10, dy: -10).contains(point)
        }
        return shape.points.contains { CGPointDistance($0, point) < 14 }
    }

    // Check if user clicked close enough to select a shape
    func findHitShape(at point: CGPoint) -> DrawingShape? {
        // Search backwards to select the topmost drawn shape first
        for shape in shapes.reversed() {
            switch shape.tool {
            case .rect, .circle:
                if shape.rect.insetBy(dx: -8, dy: -8).contains(point) {
                    return shape
                }
            case .text:
                if shape.bounds.insetBy(dx: -8, dy: -8).contains(point) {
                    return shape
                }
            case .pen:
                if shape.points.contains(where: { CGPointDistance($0, point) < 12 }) {
                    return shape
                }
            default:
                break
            }
        }
        return nil
    }

    var body: some View {
        ZStack {
            // Pure white whiteboard canvas background
            Color.white
                .ignoresSafeArea()

            // Excalidraw Dotted Grid
            DotGridView()
                .opacity(0.55)

            // Vector Rendering Canvas (Spans 100% of Screen width & height!)
            Canvas { context, size in
                for shape in shapes {
                    // 1. Draw sketchy filling first
                    if shape.tool == .rect || shape.tool == .circle {
                        if shape.fillStyle == .hachure {
                            let fillPath = sketchyHachure(rect: shape.rect, spacing: 10, roughness: 1.0)
                            context.stroke(fillPath, with: .color(shape.color.opacity(0.45)), lineWidth: 1.5)
                        } else if shape.fillStyle == .solid {
                            let fillPath = shape.tool == .rect ? Path(shape.rect) : Path(ellipseIn: shape.rect)
                            context.fill(fillPath, with: .color(shape.color.opacity(0.2)))
                        }
                    }

                    // 2. Draw outlines
                    if let cachedPath = shape.sketchyPath {
                        let strokeStyle = shape.strokeStyle == .dashed ? StrokeStyle(lineWidth: shape.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: shape.lineWidth)
                        context.stroke(cachedPath, with: .color(shape.color), style: strokeStyle)

                        if let hPath = shape.hachurePath {
                            context.stroke(hPath, with: .color(shape.color.opacity(0.45)), lineWidth: 1.5)
                        }
                    } else {
                        // Fallback for shapes without cache (e.g. legacy or during creation)
                        var outlinePath = Path()
                        switch shape.tool {
                        case .pen:
                            if shape.points.count > 1 {
                                outlinePath.addLines(shape.points)
                                let strokeStyle = shape.strokeStyle == .dashed ? StrokeStyle(lineWidth: shape.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: shape.lineWidth)
                                context.stroke(outlinePath, with: .color(shape.color), style: strokeStyle)
                            }
                        case .rect:
                            outlinePath = sketchyRect(rect: shape.rect, roughness: 1.2)
                            let strokeStyle = shape.strokeStyle == .dashed ? StrokeStyle(lineWidth: shape.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: shape.lineWidth)
                            context.stroke(outlinePath, with: .color(shape.color), style: strokeStyle)
                        case .circle:
                            outlinePath = sketchyCircle(rect: shape.rect, roughness: 1.2)
                            let strokeStyle = shape.strokeStyle == .dashed ? StrokeStyle(lineWidth: shape.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: shape.lineWidth)
                            context.stroke(outlinePath, with: .color(shape.color), style: strokeStyle)
                        default: break
                        }
                    }

                    if shape.tool == .text {
                        if let textPoint = shape.points.first {
                            context.draw(
                                Text(shape.text)
                                    .font(.system(size: shape.fontSize, weight: .bold, design: .rounded))
                                    .foregroundColor(shape.color),
                                at: textPoint,
                                anchor: .topLeading
                            )
                        }
                    }

                    // 3. Highlight Selected Shape with a gorgeous neon bounding ring
                    if selectedShapeID == shape.id {
                        let bounds = shape.bounds.insetBy(dx: -6, dy: -6)
                        let boundingPath = Path(roundedRect: bounds, cornerRadius: 6)
                        context.stroke(
                            boundingPath,
                            with: .color(Color.cyan.opacity(0.65)),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                        )
                    }
                }

                // Live drawing preview
                if let current = currentShape {
                    if current.tool == .rect || current.tool == .circle {
                        if current.fillStyle == .hachure {
                            let fillPath = sketchyHachure(rect: current.rect, spacing: 10, roughness: 1.0)
                            context.stroke(fillPath, with: .color(current.color.opacity(0.4)), lineWidth: 1.2)
                        } else if current.fillStyle == .solid {
                            let fillPath = current.tool == .rect ? Path(current.rect) : Path(ellipseIn: current.rect)
                            context.fill(fillPath, with: .color(current.color.opacity(0.15)))
                        }
                    }

                    var outlinePath = Path()
                    switch current.tool {
                    case .pen:
                        if current.points.count > 1 {
                            outlinePath.addLines(current.points)
                            let strokeStyle = current.strokeStyle == .dashed ? StrokeStyle(lineWidth: current.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: current.lineWidth)
                            context.stroke(outlinePath, with: .color(current.color), style: strokeStyle)
                        }
                    case .rect:
                        outlinePath = sketchyRect(rect: current.rect, roughness: 1.2)
                        let strokeStyle = current.strokeStyle == .dashed ? StrokeStyle(lineWidth: current.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: current.lineWidth)
                        context.stroke(outlinePath, with: .color(current.color), style: strokeStyle)
                    case .circle:
                        outlinePath = sketchyCircle(rect: current.rect, roughness: 1.2)
                        let strokeStyle = current.strokeStyle == .dashed ? StrokeStyle(lineWidth: current.lineWidth, dash: [6, 6]) : StrokeStyle(lineWidth: current.lineWidth)
                        context.stroke(outlinePath, with: .color(current.color), style: strokeStyle)
                    default:
                        break
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let pt = value.location

                        // --- 1. Selection & Repositioning/Dragging Tool Mode ---
                        if activeTool == .select {
                            if !isDraggingShape {
                                if let hit = findHitShape(at: value.startLocation) {
                                    selectedShapeID = hit.id
                                    isDraggingShape = true
                                    dragStartPoint = value.startLocation
                                    shapeOriginalPoints = hit.points
                                    shapeOriginalRect = hit.rect
                                    if hit.tool == .text {
                                        fontSize = hit.fontSize
                                    }
                                } else {
                                    selectedShapeID = nil
                                }
                            }

                            // If dragging, offset the shape coordinates instantly!
                            if isDraggingShape, let selectedID = selectedShapeID, let idx = shapes.firstIndex(where: { $0.id == selectedID }) {
                                let dx = pt.x - dragStartPoint.x
                                let dy = pt.y - dragStartPoint.y

                                if shapes[idx].tool == .rect || shapes[idx].tool == .circle {
                                    shapes[idx].rect = CGRect(
                                        x: shapeOriginalRect.origin.x + dx,
                                        y: shapeOriginalRect.origin.y + dy,
                                        width: shapeOriginalRect.width,
                                        height: shapeOriginalRect.height
                                    )
                                } else {
                                    shapes[idx].points = shapeOriginalPoints.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                                }
                            }
                            return
                        }

                        // --- 2. Eraser Mode ---
                        if activeTool == .eraser {
                            shapes.removeAll { shouldEraseShape($0, at: pt) }
                            selectedShapeID = nil
                            return
                        }

                        // --- 3. Drawing Mode ---
                        if activeTool == .text { return }

                        if currentShape == nil {
                            selectedShapeID = nil
                            currentShape = DrawingShape(
                                tool: activeTool,
                                points: [value.startLocation],
                                rect: CGRect(origin: value.startLocation, size: .zero),
                                color: strokeColor,
                                lineWidth: strokeWidth,
                                fillStyle: fillStyle,
                                strokeStyle: strokeStyle
                            )
                        } else {
                            if activeTool == .pen {
                                if let lastPt = currentShape?.points.last {
                                    if CGPointDistance(lastPt, pt) > 2 {
                                        currentShape?.points.append(pt)
                                    }
                                } else {
                                    currentShape?.points.append(pt)
                                }
                            } else if activeTool == .rect || activeTool == .circle {
                                let origin = CGPoint(
                                    x: min(value.startLocation.x, pt.x),
                                    y: min(value.startLocation.y, pt.y)
                                )
                                let size = CGSize(
                                    width: abs(pt.x - value.startLocation.x),
                                    height: abs(pt.y - value.startLocation.y)
                                )
                                currentShape?.rect = CGRect(origin: origin, size: size)
                            }
                        }
                    }
                    .onEnded { value in
                        if activeTool == .select {
                            isDraggingShape = false
                            // Update cache after drag ends
                            if let selectedID = selectedShapeID, let idx = shapes.firstIndex(where: { $0.id == selectedID }) {
                                var updated = shapes[idx]
                                if updated.tool == .rect {
                                    updated.sketchyPath = sketchyRect(rect: updated.rect)
                                    if updated.fillStyle == .hachure { updated.hachurePath = sketchyHachure(rect: updated.rect) }
                                } else if updated.tool == .circle {
                                    updated.sketchyPath = sketchyCircle(rect: updated.rect)
                                    if updated.fillStyle == .hachure { updated.hachurePath = sketchyHachure(rect: updated.rect) }
                                }
                                shapes[idx] = updated
                            }
                            return
                        }
                        if activeTool == .text {
                            textSpawnPoint = value.location
                            if let hitShape = findHitShape(at: value.location), hitShape.tool == .text {
                                selectedShapeID = hitShape.id
                                textInputVal = hitShape.text
                            } else {
                                textInputVal = ""
                            }
                            showTextInput = true
                            return
                        }
                        if var current = currentShape {
                            // Bake deterministic sketchy geometry on completion
                            if current.tool == .rect {
                                current.sketchyPath = sketchyRect(rect: current.rect)
                                if current.fillStyle == .hachure { current.hachurePath = sketchyHachure(rect: current.rect) }
                            } else if current.tool == .circle {
                                current.sketchyPath = sketchyCircle(rect: current.rect)
                                if current.fillStyle == .hachure { current.hachurePath = sketchyHachure(rect: current.rect) }
                            } else if current.tool == .pen {
                                var p = Path()
                                if current.points.count > 1 { p.addLines(current.points) }
                                current.sketchyPath = p
                            }
                            shapes.append(current)
                            currentShape = nil
                        }
                    }
            )

            // Floating Settings Panel Overlayed in Bottom-Left Corner (Whiteboard is now massive & 100% size!)
            VStack {
                Spacer()
                HStack {
                    WhiteboardSettingsSidebar(strokeWidth: $strokeWidth, strokeStyle: $strokeStyle, fillStyle: $fillStyle, fontSize: $fontSize)
                        .padding(20)
                    Spacer()
                }
            }
            .allowsHitTesting(true)

            // Centered Floating Top Toolbar (Excalidraw Dock Design)
            VStack {
                HStack(spacing: 12) {
                    ToolButton(icon: "arrow.up.and.down.and.arrow.left.and.right", tool: .select, activeTool: activeTool) { activeTool = .select }
                    ToolButton(icon: "pencil", tool: .pen, activeTool: activeTool) { activeTool = .pen; selectedShapeID = nil }
                    ToolButton(icon: "square", tool: .rect, activeTool: activeTool) { activeTool = .rect; selectedShapeID = nil }
                    ToolButton(icon: "circle", tool: .circle, activeTool: activeTool) { activeTool = .circle; selectedShapeID = nil }
                    ToolButton(icon: "textformat", tool: .text, activeTool: activeTool) { activeTool = .text }
                    ToolButton(icon: "eraser", tool: .eraser, activeTool: activeTool) { activeTool = .eraser; selectedShapeID = nil }

                    Divider().frame(height: 18).background(Color.white.opacity(0.12))

                    HStack(spacing: 6) {
                        ColorDot(color: .white, selected: strokeColor == .white) { strokeColor = .white }
                        ColorDot(color: .red, selected: strokeColor == .red) { strokeColor = .red }
                        ColorDot(color: .blue, selected: strokeColor == .blue) { strokeColor = .blue }
                        ColorDot(color: .green, selected: strokeColor == .green) { strokeColor = .green }
                    }

                    Divider().frame(height: 18).background(Color.white.opacity(0.12))

                    Button(action: { shapes.removeAll(); selectedShapeID = nil }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Color.red.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                .padding(.top, 16)

                Spacer()
            }
            .allowsHitTesting(true)

            // Gorgeous Custom Glass Text input modal (Product Design Redesign!)
            if showTextInput {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { showTextInput = false }

                    VStack(spacing: 16) {
                        Text(selectedShapeID != nil ? "Edit Whiteboard Text" : "Add Text to Whiteboard")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))

                        HStack(spacing: 8) {
                            TextField("Type something beautiful...", text: $textInputVal, onCommit: {
                                commitTextAction()
                            })
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))

                            Button(action: {
                                if textInputVal.hasPrefix("• ") {
                                    textInputVal.removeFirst(2)
                                } else {
                                    textInputVal = "• " + textInputVal
                                }
                            }) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help("Toggle Bullet Point")
                        }
                        .frame(width: 320)

                        HStack(spacing: 12) {
                            Button(action: {
                                showTextInput = false
                                textInputVal = ""
                                selectedShapeID = nil
                            }) {
                                Text("Cancel")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                commitTextAction()
                            }) {
                                Text("Save & Insert")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 7)
                                    .background(Color.blue.opacity(0.85))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(22)
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.4), radius: 25, x: 0, y: 12)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    private func commitTextAction() {
        if !textInputVal.isEmpty {
            if let selectedID = selectedShapeID, let idx = shapes.firstIndex(where: { $0.id == selectedID }) {
                shapes[idx].text = textInputVal
            } else {
                shapes.append(
                    DrawingShape(
                        tool: .text,
                        points: [textSpawnPoint],
                        text: textInputVal,
                        color: strokeColor,
                        fontSize: fontSize
                    )
                )
            }
        }
        textInputVal = ""
        showTextInput = false
        selectedShapeID = nil
    }
}

// MARK: - Kanban Board Types

enum CardPriority: String, Codable, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .gray
        }
    }
}

struct KanbanCard: Identifiable, Codable {
    var id = UUID()
    var title: String = "New Task"
    var description: String = ""
    var priority: CardPriority = .medium
    var isDone = false
    var imageData: Data? = nil
}

struct KanbanColumn: Identifiable, Codable {
    var id = UUID()
    var name: String
    var cards: [KanbanCard] = []
}

// MARK: - Pasteboard Image Helper

func pasteImageFromClipboard() -> Data? {
    let pasteboard = NSPasteboard.general
    if let image = NSImage(pasteboard: pasteboard) {
        return image.tiffRepresentation
    }
    return nil
}

// MARK: - Kanban Card View (Linear SaaS-Grade UX Redesign!)

struct KanbanCardView: View {
    var card: KanbanCard
    @State private var isHovered = false

    let onDelete: () -> Void
    let onMoveForward: (() -> Void)?
    let onMoveBackward: (() -> Void)?
    let onPasteImage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Screenshot attachment layer
            if let imgData = card.imageData, let nsImg = NSImage(data: imgData) {
                Image(nsImage: nsImg)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 130)
                    .clipped()
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
            }

            HStack {
                // Sleek Priority Pill (Dot design)
                HStack(spacing: 4) {
                    Circle()
                        .fill(card.priority.color)
                        .frame(width: 5, height: 5)
                    Text(card.priority.rawValue.uppercased())
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(card.priority.color.opacity(0.2))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(card.priority.color.opacity(0.35), lineWidth: 1))

                Spacer()

                // Fine hover options
                if isHovered {
                    HStack(spacing: 8) {
                        Button(action: onPasteImage) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Attach screenshot from clipboard")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(.red.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity)
                }
            }

            Text(card.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            if !card.description.isEmpty {
                Text(card.description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)
            }

            // Movement Chevrons (Hover based Linear layout!)
            if isHovered {
                HStack(spacing: 6) {
                    if let onBack = onMoveBackward {
                        Button(action: onBack) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Back")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3.5)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if let onForward = onMoveForward {
                        Button(action: onForward) {
                            HStack(spacing: 3) {
                                Text("Move")
                                    .font(.system(size: 8, weight: .bold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Color.blue.opacity(0.75))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue.opacity(0.2), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(Color.white.opacity(isHovered ? 0.04 : 0.02))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(isHovered ? 0.08 : 0.04), lineWidth: 1))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Kanban Column View (Linear Glass Panels)

struct KanbanColumnView: View {
    @Binding var column: KanbanColumn
    let nextColumnAction: ((KanbanCard) -> Void)?
    let prevColumnAction: ((KanbanCard) -> Void)?
    let onPasteImage: (UUID) -> Void

    @State private var showAddCard = false
    @State private var newCardTitle = ""
    @State private var newCardDesc = ""
    @State private var newCardPriority = CardPriority.medium

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text(column.name.uppercased())
                    .font(.system(size: 11.5, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Text("\(column.cards.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 4)

            // Scrollable cards panel
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(column.cards) { card in
                        KanbanCardView(card: card, onDelete: {
                            column.cards.removeAll { $0.id == card.id }
                        }, onMoveForward: nextColumnAction != nil ? {
                            nextColumnAction?(card)
                        } : nil, onMoveBackward: prevColumnAction != nil ? {
                            prevColumnAction?(card)
                        } : nil, onPasteImage: {
                            onPasteImage(card.id)
                        })
                    }

                    // Elegant Inline expanding Card Creator (No AI Slop cringy segmented pickers!)
                    if showAddCard {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Card Title...", text: $newCardTitle)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(6)

                            TextField("Details...", text: $newCardDesc)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(8)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(6)

                            // Fine custom Priority segment labels
                            HStack {
                                ForEach(CardPriority.allCases, id: \.self) { prio in
                                    Button(action: { newCardPriority = prio }) {
                                        Text(prio.rawValue)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(newCardPriority == prio ? .white : .white.opacity(0.4))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(newCardPriority == prio ? Color.white.opacity(0.12) : Color.clear)
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)

                            HStack {
                                Button(action: {
                                    showAddCard = false
                                    newCardTitle = ""
                                    newCardDesc = ""
                                }) {
                                    Text("Cancel")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.5))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.white.opacity(0.03))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button(action: {
                                    if !newCardTitle.isEmpty {
                                        let card = KanbanCard(title: newCardTitle, description: newCardDesc, priority: newCardPriority)
                                        column.cards.append(card)
                                    }
                                    showAddCard = false
                                    newCardTitle = ""
                                    newCardDesc = ""
                                }) {
                                    Text("Add Card")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.8))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    } else {
                        Button(action: { showAddCard = true }) {
                            HStack {
                                Image(systemName: "plus")
                                Text("New Item")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.02))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.04), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 290)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(0.45)
                .cornerRadius(16)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .onPasteCommand(of: [.text, .tiff]) { providers in
            let pb = NSPasteboard.general

            // 1. Handle Image Paste
            if pb.types?.contains(.tiff) == true, let _ = pasteImageFromClipboard() {
                // If we have an existing card being hovered or just add to top
                if let card = column.cards.first {
                    onPasteImage(card.id)
                }
                return
            }

            // 2. Handle Text Paste (Multi-line intelligent parsing)
            if let text = pb.string(forType: .string) {
                let lines = text.components(separatedBy: .newlines)
                for line in lines {
                    var cleaned = line.trimmingCharacters(in: .whitespaces)
                    if cleaned.isEmpty { continue }

                    // Strip Markdown bullets: "-", "*", "+", "1.", "[ ]", "[x]"
                    let patterns = [
                        "^[\\s]*[-*+][\\s]+",       // Bullets
                        "^[\\s]*[0-9]+\\.[\\s]+",   // Numbered
                        "^\\[[\\sxX]\\][\\s]*"      // Checkboxes
                    ]

                    for pattern in patterns {
                        if let regex = try? NSRegularExpression(pattern: pattern) {
                            let range = NSRange(location: 0, length: cleaned.utf16.count)
                            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
                        }
                    }

                    cleaned = cleaned.trimmingCharacters(in: .whitespaces)
                    if !cleaned.isEmpty {
                        let card = KanbanCard(title: cleaned, description: "", priority: .medium)
                        column.cards.append(card)
                    }
                }
            }
        }
    }
}

// MARK: - Kanban Board Container

struct KanbanView: View {
    @State private var todoColumn = KanbanColumn(name: "Backlog", cards: [
        KanbanCard(title: "Define UI Architecture", description: "Design glassmorphic panels and sidebar controls", priority: .high),
        KanbanCard(title: "Setup Terminal PTY", description: "Bind shell standard input/output streams natively", priority: .medium)
    ])
    @State private var progressColumn = KanbanColumn(name: "In Progress", cards: [
        KanbanCard(title: "Excalidraw Whiteboard Mode", description: "Implement vector sketchy line renderer", priority: .high)
    ])
    @State private var doneColumn = KanbanColumn(name: "Done", cards: [
        KanbanCard(title: "Click Focus Detection", description: "Overlay transparent tap listener on inactive cells", priority: .low)
    ])

    func pasteImageToCard(cardID: UUID) {
        if let data = pasteImageFromClipboard() {
            if let idx = todoColumn.cards.firstIndex(where: { $0.id == cardID }) {
                todoColumn.cards[idx].imageData = data
            } else if let idx = progressColumn.cards.firstIndex(where: { $0.id == cardID }) {
                progressColumn.cards[idx].imageData = data
            } else if let idx = doneColumn.cards.firstIndex(where: { $0.id == cardID }) {
                doneColumn.cards[idx].imageData = data
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            KanbanColumnView(column: $todoColumn, nextColumnAction: { card in
                todoColumn.cards.removeAll { $0.id == card.id }
                progressColumn.cards.append(card)
            }, prevColumnAction: nil, onPasteImage: pasteImageToCard)

            KanbanColumnView(column: $progressColumn, nextColumnAction: { card in
                progressColumn.cards.removeAll { $0.id == card.id }
                doneColumn.cards.append(card)
            }, prevColumnAction: { card in
                progressColumn.cards.removeAll { $0.id == card.id }
                todoColumn.cards.append(card)
            }, onPasteImage: pasteImageToCard)

            KanbanColumnView(column: $doneColumn, nextColumnAction: nil, prevColumnAction: { card in
                doneColumn.cards.removeAll { $0.id == card.id }
                progressColumn.cards.append(card)
            }, onPasteImage: pasteImageToCard)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 8)
    }
}

// MARK: - Unified Planner Workspace View (Whiteboard & Kanban Switcher)

struct PlannerWorkspaceView: View {
    @State private var subMode: PlannerSubMode = .whiteboard

    enum PlannerSubMode {
        case whiteboard
        case kanban
    }

    var body: some View {
        VStack(spacing: 0) {
            // Elegant Sub-Tab Switcher
            HStack(spacing: 4) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) { subMode = .whiteboard }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.and.outline")
                        Text("Whiteboard")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(subMode == .whiteboard ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(subMode == .whiteboard ? Color.white.opacity(0.08) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) { subMode = .kanban }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.3x2.fill")
                        Text("Kanban Board")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(subMode == .kanban ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(subMode == .kanban ? Color.white.opacity(0.08) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(4)
            .background(Color.black.opacity(0.25))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.04), lineWidth: 1))
            .padding(.top, 10)

            ZStack {
                if subMode == .whiteboard {
                    WhiteboardView()
                        .transition(.opacity)
                } else {
                    KanbanView()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Top Navigation Bar

struct ModeButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 12.5, weight: .bold))
            .foregroundColor(isSelected ? .white : .gray)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct TopNavigationBar: View {
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        HStack {
            // Sidebar Toggle & Segmented Switcher
            HStack(spacing: 12) {
                if manager.mode == .terminals {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            manager.showSidebar.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(manager.showSidebar ? .blue : .white.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(manager.showSidebar ? 0.12 : 0.05))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Projects Sidebar")
                }

                HStack(spacing: 4) {
                    ModeButton(title: "Terminals", icon: "terminal", isSelected: manager.mode == .terminals) {
                        withAnimation(.easeInOut(duration: 0.2)) { manager.mode = .terminals }
                    }
                    ModeButton(title: "Planner", icon: "square.and.pencil", isSelected: manager.mode == .planner) {
                        withAnimation(.easeInOut(duration: 0.2)) { manager.mode = .planner }
                    }
                }
                .padding(4)
                .background(Color.black.opacity(0.3))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.04), lineWidth: 1))
            }

            Spacer()

            // Elegant Apple-Style New Tab actions
            if manager.mode == .terminals {
                HStack(spacing: 6) {
                    Button(action: { manager.addSession() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("New Tab")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("t", modifiers: .command)

                    AgentPresetMenu(manager: manager)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.leading, (manager.mode == .terminals && manager.showSidebar) ? 14 : 70)
    }
}

struct AgentPresetMenu: View {
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        Menu {
            ForEach(AgentPreset.allCases, id: \.self) { preset in
                Button(action: { manager.runPreset(preset) }) {
                    HStack {
                        Image(systemName: preset.symbolName)
                        Text(preset.title)
                        Spacer()
                        Text("⌘\(preset.shortcut.uppercased())")
                            .foregroundColor(.gray)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                AgentLogoBadge(text: "G", color: .blue)
                AgentLogoBadge(text: "AI", color: .green)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Open agent tab")
    }
}

struct AgentLogoBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: text.count > 1 ? 8 : 10, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 18, height: 18)
            .background(color.opacity(0.8))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Visual Effects

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Main Application Content (Terminals Stay Alive Permanently)

struct ContentView: View {
    @StateObject var workspaceManager = WorkspaceManager()

    var body: some View {
        HStack(spacing: 0) {
            if workspaceManager.mode == .terminals && workspaceManager.showSidebar {
                ProjectsSidebarView(manager: workspaceManager)
                    .frame(width: 240)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                TopNavigationBar(manager: workspaceManager)
                    .zIndex(10)

                ZStack {
                    if workspaceManager.mode == .terminals {
                        DynamicGridView(manager: workspaceManager)
                            .transition(.opacity)
                    }

                    if workspaceManager.mode == .planner {
                        PlannerWorkspaceView()
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: workspaceManager.showSidebar)
        .animation(.easeInOut(duration: 0.12), value: workspaceManager.mode)
        .background(Color.clear)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewTerminal"))) { _ in
            if workspaceManager.mode == .terminals {
                workspaceManager.addSession()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseTerminal"))) { _ in
            if workspaceManager.mode == .terminals {
                workspaceManager.removeActiveSession()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RestoreSessions"))) { _ in
            if workspaceManager.mode == .terminals {
                workspaceManager.restoreSessions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RunAgentPreset"))) { notification in
            guard let rawValue = notification.object as? String, let preset = AgentPreset(rawValue: rawValue) else {
                return
            }
            workspaceManager.runPreset(preset)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ClearAgentChat"))) { _ in
            if workspaceManager.mode == .terminals {
                workspaceManager.clearActiveAgentChat()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PasteImage"))) { _ in
            workspaceManager.handleClipboardImage()
        }
    }
}

// MARK: - Aesthetic Left Sidebar for Projects Workspace

struct ProjectsSidebarView: View {
    @ObservedObject var manager: WorkspaceManager
    @State private var hoveredProject: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.trianglebadge.gearshape")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.blue)

                Text("WORKSPACE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Button(action: {
                    manager.refreshProjects()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Refresh projects list")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .padding(.top, 38)

            Divider()
                .background(Color.white.opacity(0.08))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PROJECTS")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.0)
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    if manager.projectDirectories.isEmpty {
                        Text("No projects found")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(manager.projectDirectories, id: \.self) { dir in
                            ProjectRowView(dir: dir, manager: manager, hoveredProject: $hoveredProject)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(0.4)
                .background(Color.black.opacity(0.15))
        )
        .overlay(
            HStack {
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 1)
            }
        )
    }
}

struct ProjectRowView: View {
    let dir: URL
    @ObservedObject var manager: WorkspaceManager
    @Binding var hoveredProject: URL?

    var isHovered: Bool { hoveredProject == dir }

    var body: some View {
        Button(action: {
            manager.addSession(in: dir)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isHovered ? .blue : .white.opacity(0.6))
                    .frame(width: 18)

                Text(dir.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(isHovered ? .white : .white.opacity(0.75))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.85)

                Spacer()

                if isHovered {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.blue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                if hovering {
                    hoveredProject = dir
                } else if hoveredProject == dir {
                    hoveredProject = nil
                }
            }
        }
    }
}

// MARK: - App Icon Drawing Generator

func generateAppIcon() -> NSImage {
    let size = NSSize(width: 512, height: 512)
    let image = NSImage(size: size)

    image.lockFocus()

    // Explicitly clear background to transparent
    NSColor.clear.set()
    NSRect(origin: .zero, size: size).fill()

    // Draw background rounded rect
    let rect = NSRect(origin: .zero, size: size).insetBy(dx: 32, dy: 32)
    let path = NSBezierPath(roundedRect: rect, xRadius: 112, yRadius: 112)

    // Sleek solid black base
    NSColor.black.setFill()
    path.fill()

    // Neon Cyan border
    NSColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0).setStroke()
    path.lineWidth = 14
    path.stroke()

    // Cyber shadow/glow
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.5)
    shadow.shadowBlurRadius = 32
    shadow.shadowOffset = .zero
    shadow.set()

    // Prompt sign text ">_"
    let font = NSFont.systemFont(ofSize: 180, weight: .bold)
    let text = ">_"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .shadow: shadow
    ]

    let textSize = text.size(withAttributes: attributes)
    let textRect = NSRect(
        x: rect.midX - textSize.width / 2,
        y: rect.midY - textSize.height / 2 - 20,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: attributes)

    image.unlockFocus()
    return image
}

// MARK: - macOS App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    @objc func newTerminal() { NotificationCenter.default.post(name: NSNotification.Name("NewTerminal"), object: nil) }
    @objc func closeTerminal() { NotificationCenter.default.post(name: NSNotification.Name("CloseTerminal"), object: nil) }
    @objc func newOpenAICodexTerminal() { NotificationCenter.default.post(name: NSNotification.Name("RunAgentPreset"), object: AgentPreset.openAICodex.rawValue) }
    @objc func newGoogleAntigravityTerminal() { NotificationCenter.default.post(name: NSNotification.Name("RunAgentPreset"), object: AgentPreset.googleAntigravity.rawValue) }
    @objc func restorePreviousSession() { NotificationCenter.default.post(name: NSNotification.Name("RestoreSessions"), object: nil) }

    func applicationWillTerminate(_ notification: Notification) {
        WorkspaceManager.shared?.saveSessionState()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()

        // Setup Beautiful Dynamically Rendered App Icon
        if let iconImage = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = iconImage
        } else {
            NSApp.applicationIconImage = generateAppIcon()
        }

        // Globally intercept and route Cmd+C/V/X/A and Option+Q perfectly
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let hasOption = event.modifierFlags.contains(.option)
            let hasCmd = event.modifierFlags.contains(.command)
            let hasControl = event.modifierFlags.contains(.control)
            let hasShift = event.modifierFlags.contains(.shift)

            // 1. Intercept Cmd + W for Terminal Close Tab
            if hasCmd && !hasOption && !hasControl && !hasShift && event.charactersIgnoringModifiers == "w" {
                NotificationCenter.default.post(name: Notification.Name("CloseTerminal"), object: nil)
                return nil // Swallow
            }

            // Cmd + T for New Terminal
            if hasCmd && !hasOption && !hasControl && !hasShift && event.charactersIgnoringModifiers == "t" {
                NotificationCenter.default.post(name: Notification.Name("NewTerminal"), object: nil)
                return nil
            }

            // Cmd + Shift + T for Restore Sessions
            if hasCmd && !hasOption && !hasControl && hasShift && event.charactersIgnoringModifiers?.lowercased() == "t" {
                NotificationCenter.default.post(name: Notification.Name("RestoreSessions"), object: nil)
                return nil
            }

            // Cmd + G for Google Antigravity
            if hasCmd && !hasOption && !hasControl && !hasShift && event.charactersIgnoringModifiers == "g" {
                NotificationCenter.default.post(name: Notification.Name("RunAgentPreset"), object: AgentPreset.googleAntigravity.rawValue)
                return nil
            }

            // Cmd + O for OpenAI Codex
            if hasCmd && !hasOption && !hasControl && !hasShift && event.charactersIgnoringModifiers == "o" {
                NotificationCenter.default.post(name: Notification.Name("RunAgentPreset"), object: AgentPreset.openAICodex.rawValue)
                return nil
            }

            if hasCmd && !hasOption && !hasControl && !hasShift && (event.charactersIgnoringModifiers == "\u{7F}" || event.keyCode == 51) {
                NotificationCenter.default.post(name: Notification.Name("ClearAgentChat"), object: nil)
                return nil
            }

            // Cmd + V for Clipboard Image/File Handling before standard text paste can consume it
            if hasCmd && !hasOption && !hasControl && !hasShift && event.charactersIgnoringModifiers == "v" {
                let pasteboard = NSPasteboard.general
                let hasFile = pasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
                let hasImage = pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
                    || pasteboard.types?.contains(.png) == true
                    || pasteboard.types?.contains(.tiff) == true
                let hasPlainText = pasteboard.string(forType: .string)?.isEmpty == false

                if hasFile || (hasImage && !hasPlainText) {
                    NotificationCenter.default.post(name: Notification.Name("PasteImage"), object: nil)
                    return nil
                }
            }

            // 2. Dynamic Copy and Paste Hotkey Routing (Fixes system first-responder swallowing!)
            if hasCmd && !hasOption && !hasControl && !hasShift {
                if event.charactersIgnoringModifiers == "c" {
                    if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) { return nil }
                } else if event.charactersIgnoringModifiers == "v" {
                    if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) { return nil }
                } else if event.charactersIgnoringModifiers == "x" {
                    if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) { return nil }
                } else if event.charactersIgnoringModifiers == "a" {
                    if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) { return nil }
                }
            }

            return event
        }

        let rect = NSRect(x: 100, y: 100, width: 1400, height: 900)
        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false

        // Configure Apple Pro high-performance graphics pipeline (sRGB & ProMotion 120Hz support)
        window.allowsConcurrentViewDrawing = true
        window.colorSpace = NSColorSpace.sRGB
        window.sharingType = .readWrite

        let hostingView = NSHostingView(
            rootView: ContentView()
                .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                .clipShape(RoundedRectangle(cornerRadius: 18)) // Rounded corners like standard macOS apps
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1) // Subtle premium outline border
                )
                .ignoresSafeArea()
        )
        hostingView.wantsLayer = true
        hostingView.layer?.drawsAsynchronously = true
        hostingView.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        window.contentView = hostingView

        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func setupMenu() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        // App Menu (Cmd + Q)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let quitItem = NSMenuItem(title: "Quit MyTerm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)

        // Edit Menu (Crucial for Copy and Paste shortcuts to map correctly across cocoa/system frameworks!)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        // File Menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        // Cmd + T
        let newItem = NSMenuItem(title: "New Terminal", action: #selector(AppDelegate.newTerminal), keyEquivalent: "t")
        fileMenu.addItem(newItem)

        // Cmd + Shift + T
        let restoreItem = NSMenuItem(title: "Restore Previous Session", action: #selector(AppDelegate.restorePreviousSession), keyEquivalent: "t")
        restoreItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(restoreItem)

        let openAICodexItem = NSMenuItem(title: "New OpenAI Codex Tab", action: #selector(AppDelegate.newOpenAICodexTerminal), keyEquivalent: "o")
        openAICodexItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(openAICodexItem)

        let googleAntigravityItem = NSMenuItem(title: "New Google Antigravity Tab", action: #selector(AppDelegate.newGoogleAntigravityTerminal), keyEquivalent: "g")
        googleAntigravityItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(googleAntigravityItem)

        // Cmd + W
        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(AppDelegate.closeTerminal), keyEquivalent: "w")
        closeItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(closeItem)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
