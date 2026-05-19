import SwiftUI
import AppKit
import Foundation
import Combine

// MARK: - Models

struct ANSISpan: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let color: Color
    let isBold: Bool
}

struct TerminalOutput: Identifiable, Equatable {
    let id = UUID()
    let command: String
    var rawOutput: String
    
    var ansiSpans: [ANSISpan] {
        guard !rawOutput.isEmpty else { return [] }
        return parseANSI(rawOutput)
    }
}

class TerminalSession: ObservableObject, Identifiable {
    let id = UUID()
    let index: String
    @Published var name: String
    @Published var path: String = "~/projects/nebula"
    @Published var tag: String = "idle"
    @Published var tagColor: Color = .gray
    @Published var commandInput: String = ""
    @Published var outputs: [TerminalOutput] = []
    
    // Custom state control for rich widgets
    @Published var widgetType: String = "none" // "planning", "audit", "explore", "build", "review", "worktree", "none"
    @Published var isRunning: Bool = false
    
    // Build Widget state
    @Published var buildProgress: Double = 0.68
    @Published var buildStep: Int = 3
    
    // Animation timer
    private var timer: AnyCancellable?
    private var process: Process?
    private var outputPipe: Pipe?
    
    init(index: String, name: String, tag: String = "idle", tagColor: Color = .gray, widgetType: String = "none") {
        self.index = index
        self.name = name
        self.tag = tag
        self.tagColor = tagColor
        self.widgetType = widgetType
        
        if widgetType == "build" {
            startBuildAnimation()
        }
    }
    
    func executeCommand() {
        let cmd = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        
        // Clear input
        commandInput = ""
        
        // 1. Check for built-in dashboard commands/demos
        if cmd == "build" || cmd == "npm run build" {
            self.outputs.append(TerminalOutput(command: cmd, rawOutput: "Initializing build pipeline..."))
            self.widgetType = "build"
            self.tag = "build"
            self.tagColor = .purple
            startBuildAnimation()
            return
        }
        
        if cmd == "audit" {
            self.outputs.append(TerminalOutput(command: cmd, rawOutput: "Running vulnerability scanners..."))
            self.widgetType = "audit"
            self.tag = "audit"
            self.tagColor = .blue
            return
        }
        
        if cmd == "review" {
            self.outputs.append(TerminalOutput(command: cmd, rawOutput: "Analyzing local git diffs..."))
            self.widgetType = "review"
            self.tag = "review"
            self.tagColor = .purple
            return
        }
        
        if cmd == "explore" {
            self.outputs.append(TerminalOutput(command: cmd, rawOutput: "Starting explorer agent..."))
            self.widgetType = "explore"
            self.tag = "explore"
            self.tagColor = .green
            return
        }
        
        if cmd == "clear" {
            self.outputs.removeAll()
            self.widgetType = "none"
            self.tag = "idle"
            self.tagColor = .gray
            return
        }
        
        if cmd.hasPrefix("cd ") {
            let directory = cmd.replacingOccurrences(of: "cd ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let expanded = (directory as NSString).expandingTildeInPath
            
            // Check if directory exists
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) && isDir.boolValue {
                self.path = directory
                self.outputs.append(TerminalOutput(command: cmd, rawOutput: "Changed directory to \(directory)"))
            } else {
                self.outputs.append(TerminalOutput(command: cmd, rawOutput: "cd: no such file or directory: \(directory)"))
            }
            return
        }
        
        // 2. Fallback to executing standard system command in zsh!
        runSystemCommand(cmd)
    }
    
    private func runSystemCommand(_ cmd: String) {
        self.isRunning = true
        self.widgetType = "none"
        self.tag = "running"
        self.tagColor = .yellow
        
        let outputEntry = TerminalOutput(command: cmd, rawOutput: "")
        self.outputs.append(outputEntry)
        let outputIndex = self.outputs.count - 1
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", cmd]
        
        // Inherit exact environment variables for normal shell permissions
        proc.environment = ProcessInfo.processInfo.environment
        
        // Set running directory
        let expandedPath = (path as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expandedPath) {
            proc.currentDirectoryURL = URL(fileURLWithPath: expandedPath)
        }
        
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        
        self.process = proc
        self.outputPipe = pipe
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if outputIndex < self.outputs.count {
                        self.outputs[outputIndex].rawOutput += text
                    }
                }
            }
        }
        
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRunning = false
                self.tag = "idle"
                self.tagColor = .gray
                self.process = nil
                self.outputPipe = nil
            }
        }
        
        do {
            try proc.run()
        } catch {
            self.isRunning = false
            self.tag = "error"
            self.tagColor = .red
            if outputIndex < self.outputs.count {
                self.outputs[outputIndex].rawOutput = "Error launching command: \(error.localizedDescription)"
            }
        }
    }
    
    private func startBuildAnimation() {
        timer?.cancel()
        buildProgress = 0.0
        buildStep = 0
        
        timer = Timer.publish(every: 0.15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.buildProgress < 1.0 {
                    self.buildProgress += 0.015
                    
                    // Progress stages
                    if self.buildProgress > 0.20 && self.buildStep == 0 {
                        self.buildStep = 1
                    } else if self.buildProgress > 0.45 && self.buildStep == 1 {
                        self.buildStep = 2
                    } else if self.buildProgress > 0.68 && self.buildStep == 2 {
                        self.buildStep = 3
                    } else if self.buildProgress > 0.85 && self.buildStep == 3 {
                        self.buildStep = 4
                    }
                } else {
                    self.buildProgress = 1.0
                    self.buildStep = 5
                    self.tag = "idle"
                    self.tagColor = .gray
                    self.timer?.cancel()
                }
            }
    }
}

// MARK: - ANSI Color Parser

func parseANSI(_ input: String) -> [ANSISpan] {
    var spans: [ANSISpan] = []
    let parts = input.components(separatedBy: "\u{001B}[")
    
    if let first = parts.first, !first.isEmpty {
        spans.append(ANSISpan(text: first, color: .white, isBold: false))
    }
    
    var currentColor = Color.white
    var currentBold = false
    
    for part in parts.dropFirst() {
        guard !part.isEmpty else { continue }
        
        if let mIndex = part.firstIndex(of: "m") {
            let codeString = part[..<mIndex]
            let remainingText = part[part.index(after: mIndex)...]
            
            let codes = codeString.components(separatedBy: ";")
            for code in codes {
                switch code {
                case "0":
                    currentColor = .white
                    currentBold = false
                case "1":
                    currentBold = true
                case "30": currentColor = .black
                case "31": currentColor = Color(red: 0.95, green: 0.35, blue: 0.35) // Elegant red
                case "32": currentColor = Color(red: 0.35, green: 0.85, blue: 0.45) // Elegant green
                case "33": currentColor = Color(red: 0.95, green: 0.80, blue: 0.35) // Elegant yellow
                case "34": currentColor = Color(red: 0.35, green: 0.60, blue: 0.95) // Elegant blue
                case "35": currentColor = Color(red: 0.80, green: 0.45, blue: 0.95) // Elegant magenta
                case "36": currentColor = Color(red: 0.35, green: 0.85, blue: 0.95) // Elegant cyan
                case "37": currentColor = .white
                case "90": currentColor = .gray
                default: break
                }
            }
            
            if !remainingText.isEmpty {
                spans.append(ANSISpan(text: String(remainingText), color: currentColor, isBold: currentBold))
            }
        } else {
            spans.append(ANSISpan(text: "\u{001B}[" + part, color: currentColor, isBold: currentBold))
        }
    }
    
    return spans
}

// MARK: - Visual Effect (Glassmorphism)

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

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Helper Sparkline Line Chart

struct Sparkline: Shape {
    let dataPoints: [Double]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard dataPoints.count > 1 else { return path }
        
        let width = rect.width
        let height = rect.height
        let stepX = width / CGFloat(dataPoints.count - 1)
        
        let minY = dataPoints.min() ?? 0
        let maxY = dataPoints.max() ?? 1
        let range = maxY - minY == 0 ? 1 : maxY - minY
        
        let points = dataPoints.enumerated().map { index, value -> CGPoint in
            let x = CGFloat(index) * stepX
            let normalizedY = CGFloat((value - minY) / range)
            // Flip vertical axis for screen coordinates
            let y = height - (normalizedY * height * 0.7) - (height * 0.15)
            return CGPoint(x: x, y: y)
        }
        
        path.move(to: points[0])
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }
        
        return path
    }
}

// MARK: - Custom Glassmorphic Card View

struct GlassCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(Color.black.opacity(0.35))
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.02),
                            Color.purple.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Views: Sidebar

struct SidebarView: View {
    @ObservedObject var workspaceManager: WorkspaceManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            // Header Logo
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .purple.opacity(0.4), radius: 5)
                
                Text("MyTerm")
                    .font(.title2)
                    .bold()
                    .foregroundColor(.white)
            }
            .padding(.top, 20)
            
            // Workspaces section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("WORKSPACES")
                        .font(.caption2)
                        .bold()
                        .foregroundColor(.gray.opacity(0.8))
                        .tracking(1)
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2.fill")
                        .foregroundColor(.purple)
                    
                    Text("Dev Workspace")
                        .bold()
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("\(workspaceManager.sessions.count)")
                        .font(.caption)
                        .bold()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.3))
                        .clipShape(Capsule())
                        .foregroundColor(.purple.opacity(0.9))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }
            
            // Navigation Links
            VStack(alignment: .leading, spacing: 15) {
                NavigationLinkItem(icon: "terminal.fill", label: "Sessions", isActive: true)
                NavigationLinkItem(icon: "person.2.fill", label: "Agents")
                NavigationLinkItem(icon: "clock.fill", label: "History")
                NavigationLinkItem(icon: "note.text", label: "Snippets")
            }
            
            Spacer()
            
            // Pulse Sparkline Widget
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: .green, radius: 4)
                    
                    Text("Active")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                
                Text("\(workspaceManager.sessions.count) sessions")
                    .font(.caption2)
                    .foregroundColor(.gray)
                
                // Pulsing Sparkline Path
                Sparkline(dataPoints: [2.0, 3.5, 2.8, 4.2, 3.0, 5.5, 4.8, 6.2, 5.0, 7.5, 6.8])
                    .stroke(
                        LinearGradient(
                            colors: [.green.opacity(0.8), .teal.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .frame(height: 30)
                    .background(
                        Sparkline(dataPoints: [2.0, 3.5, 2.8, 4.2, 3.0, 5.5, 4.8, 6.2, 5.0, 7.5, 6.8])
                            .fill(
                                LinearGradient(
                                    colors: [.green.opacity(0.15), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }
            .padding(14)
            .background(Color.black.opacity(0.2))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
            
            // Footer Action Bar
            HStack {
                Button(action: {}) {
                    Image(systemName: "moon.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .font(.title3)
            .padding(.bottom, 15)
        }
        .padding(.horizontal, 18)
        .frame(width: 230)
        .background(Color.black.opacity(0.25))
    }
}

struct NavigationLinkItem: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(isActive ? .white : .gray)
            
            Text(label)
                .foregroundColor(isActive ? .white : .gray)
                .bold(isActive)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isActive ? Color.white.opacity(0.04) : Color.clear)
        .cornerRadius(8)
    }
}

// MARK: - Views: Top Toolbar

struct ToolbarView: View {
    @ObservedObject var workspaceManager: WorkspaceManager
    
    private var leftBreadcrumbs: some View {
        HStack(spacing: 8) {
            Text("Workspace")
                .foregroundColor(.gray)
            
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.gray)
            
            HStack {
                Text("Dev Workspace")
                    .foregroundColor(.white)
                    .bold()
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .font(.subheadline)
    }
    
    private var layoutControls: some View {
        HStack(spacing: 15) {
            LayoutButton(icon: "square.dashed", active: workspaceManager.currentLayout == .single) {
                workspaceManager.currentLayout = .single
            }
            LayoutButton(icon: "square.split.2x1", active: workspaceManager.currentLayout == .doubleHorizontal) {
                workspaceManager.currentLayout = .doubleHorizontal
            }
            LayoutButton(icon: "square.split.1x2", active: workspaceManager.currentLayout == .doubleVertical) {
                workspaceManager.currentLayout = .doubleVertical
            }
            LayoutButton(icon: "square.split.2x2", active: workspaceManager.currentLayout == .quad) {
                workspaceManager.currentLayout = .quad
            }
            LayoutButton(icon: "rectangle.grid.3x2", active: workspaceManager.currentLayout == .hex) {
                workspaceManager.currentLayout = .hex
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.2))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private var rightControls: some View {
        HStack(spacing: 15) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            Image(systemName: "terminal")
                .foregroundColor(.gray)
            
            Image(systemName: "slider.horizontal.3")
                .foregroundColor(.gray)
            
            Image(systemName: "gearshape")
                .foregroundColor(.gray)
            
            Text("M")
                .font(.caption)
                .bold()
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.purple)
                .clipShape(Circle())
        }
        .font(.title3)
    }
    
    var body: some View {
        HStack {
            leftBreadcrumbs
            Spacer()
            layoutControls
            Spacer()
            rightControls
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.1))
    }
}

struct LayoutButton: View {
    let icon: String
    let active: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(active ? .purple : .gray)
                .scaleEffect(active ? 1.1 : 1.0)
                .animation(.spring(), value: active)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Views: Pane / Session Card

struct PaneView: View {
    @ObservedObject var session: TerminalSession
    @State private var autoscroll = true
    
    var body: some View {
        GlassCard {
            // Pane Header
            HStack(spacing: 10) {
                Text(session.index)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.gray)
                
                Text(session.name)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.white)
                
                Text(session.path)
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.8))
                
                Spacer()
                
                // Status Pill
                Text(session.tag)
                    .font(.caption2)
                    .bold()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(session.tagColor.opacity(0.18))
                    .foregroundColor(session.tagColor)
                    .clipShape(Capsule())
                
                Button(action: {}) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.02))
            
            Divider()
                .background(Color.white.opacity(0.06))
            
            // Pane Workspace Content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        
                        // 1. Render Active Dashboard Widget (If active)
                        if session.widgetType == "planning" {
                            PlanningWidgetView()
                        } else if session.widgetType == "audit" {
                            AuditWidgetView()
                        } else if session.widgetType == "explore" {
                            ExploreWidgetView()
                        } else if session.widgetType == "build" {
                            BuildWidgetView(progress: session.buildProgress, step: session.buildStep)
                        } else if session.widgetType == "review" {
                            ReviewWidgetView()
                        } else if session.widgetType == "worktree" {
                            WorktreeWidgetView()
                        }
                        
                        // 2. Render Historical Command Log & Native CLI Outputs
                        ForEach(session.outputs) { out in
                            VStack(alignment: .leading, spacing: 6) {
                                // Render original typed command line
                                HStack(spacing: 6) {
                                    Text(">")
                                        .foregroundColor(.purple)
                                        .bold()
                                    Text(out.command)
                                        .foregroundColor(.white)
                                        .bold()
                                }
                                .font(.system(.body, design: .monospaced))
                                
                                // Render formatted CLI Output
                                if !out.rawOutput.isEmpty {
                                    ANSITextView(spans: out.ansiSpans)
                                        .padding(.leading, 12)
                                        .textSelection(.enabled)
                                }
                            }
                            .id(out.id)
                        }
                        
                        // Empty anchor for autoscroll
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: session.outputs.count) {
                    if autoscroll {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.06))
            
            // Pane Command Input Footer
            HStack {
                Text(">")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.purple)
                    .bold()
                
                TextField("Type a command...", text: $session.commandInput, onCommit: {
                    session.executeCommand()
                })
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                
                Spacer()
                
                // Pulse loading spinner when active zsh command runs
                if session.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                } else {
                    Button(action: {
                        session.executeCommand()
                    }) {
                        Image(systemName: "arrow.turn.down.left")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.2))
        }
    }
}

// MARK: - Rich Console Text View with ANSI Colors

struct ANSITextView: View {
    let spans: [ANSISpan]
    
    var body: some View {
        var builder = Text("")
        for span in spans {
            var textRun = Text(span.text)
                .foregroundColor(span.color)
            if span.isBold {
                textRun = textRun.bold()
            }
            builder = builder + textRun
        }
        
        return builder
            .font(.system(.body, design: .monospaced))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Dynamic Split Grid layout

class WorkspaceManager: ObservableObject {
    enum Layout {
        case single
        case doubleHorizontal
        case doubleVertical
        case quad
        case hex
    }
    
    @Published var currentLayout: Layout = .hex
    @Published var sessions: [TerminalSession] = []
    
    init() {
        self.sessions = [
            TerminalSession(index: "01", name: "Planning", tag: "plan", tagColor: .purple, widgetType: "planning"),
            TerminalSession(index: "02", name: "Audit", tag: "audit", tagColor: .blue, widgetType: "audit"),
            TerminalSession(index: "03", name: "Explore", tag: "explore", tagColor: .green, widgetType: "explore"),
            TerminalSession(index: "04", name: "Build", tag: "build", tagColor: .purple, widgetType: "build"),
            TerminalSession(index: "05", name: "Review", tag: "review", tagColor: .purple, widgetType: "review"),
            TerminalSession(index: "06", name: "Worktree", tag: "idle", tagColor: .gray, widgetType: "worktree")
        ]
    }
}

struct GridContainerView: View {
    @ObservedObject var workspaceManager: WorkspaceManager
    
    var body: some View {
        VStack(spacing: 0) {
            switch workspaceManager.currentLayout {
            case .single:
                if workspaceManager.sessions.count > 0 {
                    PaneView(session: workspaceManager.sessions[0])
                        .padding(15)
                }
                
            case .doubleHorizontal:
                HSplitView {
                    if workspaceManager.sessions.count > 0 {
                        PaneView(session: workspaceManager.sessions[0])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if workspaceManager.sessions.count > 1 {
                        PaneView(session: workspaceManager.sessions[1])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(15)
                
            case .doubleVertical:
                VSplitView {
                    if workspaceManager.sessions.count > 0 {
                        PaneView(session: workspaceManager.sessions[0])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if workspaceManager.sessions.count > 1 {
                        PaneView(session: workspaceManager.sessions[1])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(15)
                
            case .quad:
                HSplitView {
                    VSplitView {
                        if workspaceManager.sessions.count > 0 {
                            PaneView(session: workspaceManager.sessions[0])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if workspaceManager.sessions.count > 1 {
                            PaneView(session: workspaceManager.sessions[1])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    VSplitView {
                        if workspaceManager.sessions.count > 2 {
                            PaneView(session: workspaceManager.sessions[2])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if workspaceManager.sessions.count > 3 {
                            PaneView(session: workspaceManager.sessions[3])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(15)
                
            case .hex:
                HSplitView {
                    VSplitView {
                        if workspaceManager.sessions.count > 0 {
                            PaneView(session: workspaceManager.sessions[0])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if workspaceManager.sessions.count > 3 {
                            PaneView(session: workspaceManager.sessions[3])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    VSplitView {
                        if workspaceManager.sessions.count > 1 {
                            PaneView(session: workspaceManager.sessions[1])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if workspaceManager.sessions.count > 4 {
                            PaneView(session: workspaceManager.sessions[4])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    VSplitView {
                        if workspaceManager.sessions.count > 2 {
                            PaneView(session: workspaceManager.sessions[2])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if workspaceManager.sessions.count > 5 {
                            PaneView(session: workspaceManager.sessions[5])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(15)
            }
        }
    }
}

// MARK: - GUI Dashboard Widgets (Rich Output UI)

struct PlanningWidgetView: View {
    @State private var thinkingPulse = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                TaskRowView(type: "plan", title: "Type and shared interface", time: "4m")
                TaskRowView(type: "code", title: "Frontend preview", time: "4m")
                TaskRowView(type: "plan", title: "Detailed backend fix impl", time: "12m")
                TaskRowView(type: "bug", title: "Confirm root cause", time: "2m")
            }
            
            Text("Design locked. I'll ship the fix and coupon codes will finally show the real price.")
                .font(.body)
                .foregroundColor(.white.opacity(0.85))
                .lineSpacing(4)
                .padding(.top, 5)
            
            HStack(spacing: 8) {
                Image(systemName: "cloud.fill")
                    .foregroundColor(.blue.opacity(0.8))
                Text("Thinking...")
                    .font(.subheadline)
                    .italic()
                    .foregroundColor(.gray)
                    .opacity(thinkingPulse ? 0.3 : 1.0)
                    .animation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: thinkingPulse)
            }
            .padding(.top, 5)
            .onAppear {
                thinkingPulse = true
            }
        }
    }
}

struct TaskRowView: View {
    let type: String
    let title: String
    let time: String
    
    var bulletColor: Color {
        switch type {
        case "plan": return .blue
        case "code": return .purple
        case "bug": return .pink
        default: return .gray
        }
    }
    
    var body: some View {
        HStack {
            Circle()
                .fill(bulletColor)
                .frame(width: 6, height: 6)
            
            Text(type)
                .font(.caption2)
                .bold()
                .foregroundColor(bulletColor)
                .frame(width: 42, alignment: .leading)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
            
            Text(time)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

struct AuditWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 6) {
                AuditRowView(tool: "security-auditor", action: "Audit", time: "2m 13s")
                AuditRowView(tool: "deps-auditor", action: "Audit", time: "2m 21s")
                AuditRowView(tool: "infra-auditor", action: "Audit", time: "2m 44s")
            }
            
            HStack {
                Text("@agent")
                    .foregroundColor(.purple)
                    .bold()
                Text("audit the billing module")
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text("19:29")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .font(.system(.subheadline, design: .monospaced))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 6, height: 6)
                    Text("42 findings")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.white)
                }
                
                Grid(alignment: .leading, horizontalSpacing: 25, verticalSpacing: 6) {
                    GridRow {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 5, height: 5)
                            Text("Critical").foregroundColor(.gray)
                        }
                        Text("2").bold().foregroundColor(.white)
                    }
                    GridRow {
                        HStack(spacing: 6) {
                            Circle().fill(Color.orange).frame(width: 5, height: 5)
                            Text("High").foregroundColor(.gray)
                        }
                        Text("7").bold().foregroundColor(.white)
                    }
                    GridRow {
                        HStack(spacing: 6) {
                            Circle().fill(Color.yellow).frame(width: 5, height: 5)
                            Text("Medium").foregroundColor(.gray)
                        }
                        Text("23").bold().foregroundColor(.white)
                    }
                    GridRow {
                        HStack(spacing: 6) {
                            Circle().fill(Color.blue).frame(width: 5, height: 5)
                            Text("Low").foregroundColor(.gray)
                        }
                        Text("10").bold().foregroundColor(.white)
                    }
                }
                .font(.caption)
                .padding(.leading, 12)
            }
        }
    }
}

struct AuditRowView: View {
    let tool: String
    let action: String
    let time: String
    
    var body: some View {
        HStack {
            Text("×")
                .foregroundColor(.red)
                .bold()
            Text(tool)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
            
            Spacer()
            
            Text(action)
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 60, alignment: .leading)
            
            Text(time)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.gray)
        }
    }
}

struct ExploreWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("@agent")
                    .foregroundColor(.purple)
                    .bold()
                Text("explore marketing website")
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text("19:27")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .font(.system(.subheadline, design: .monospaced))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 8) {
                ExploreCheckRow(completed: true, text: "Thought for 3.0s")
                ExploreCheckRow(completed: true, text: "Plan mode entered")
                ExploreCheckRow(completed: true, text: "Scanned sitemap.xml")
                ExploreCheckRow(completed: true, text: "Explored 28 pages")
                ExploreCheckRow(completed: true, text: "Captured 47 screenshots")
                ExploreCheckRow(completed: true, text: "Wrote summary.md")
                
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Task completed in 2m 21s")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.white)
                }
                .padding(.top, 4)
            }
        }
    }
}

struct ExploreCheckRow: View {
    let completed: Bool
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(completed ? .green : .gray)
            Text(text)
                .font(.subheadline)
                .foregroundColor(completed ? .white.opacity(0.9) : .gray)
        }
    }
}

struct BuildWidgetView: View {
    let progress: Double
    let step: Int
    @State private var rotationAngle = 0.0
    
    var body: some View {
        VStack(alignment: .center, spacing: 15) {
            
            // Rotating loader
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.05), lineWidth: 3)
                    .frame(width: 48, height: 48)
                
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.purple, .pink, .clear],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(rotationAngle))
                    .onAppear {
                        withAnimation(Animation.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            rotationAngle = 360
                        }
                    }
            }
            .padding(.top, 5)
            
            VStack(spacing: 4) {
                Text("Build pipeline running")
                    .font(.headline)
                    .bold()
                    .foregroundColor(.white)
                
                Text("Compiling assets and running tests...")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            // Execution stages
            VStack(alignment: .leading, spacing: 8) {
                BuildStepRow(completed: step >= 1, text: "Install dependencies", duration: "1.2s")
                BuildStepRow(completed: step >= 2, text: "Type check", duration: "2.8s")
                BuildStepRow(completed: step >= 3, text: "Build production bundle", duration: "5.6s")
                BuildStepRow(completed: step >= 4, text: "Run tests", duration: "", isPending: step < 4)
                BuildStepRow(completed: step >= 5, text: "Upload artifacts", duration: "", isPending: step < 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            
            // Progress Bar widget
            HStack(spacing: 12) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(progress), height: 6)
                    }
                }
                .frame(height: 6)
                
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .bold()
                    .foregroundColor(.gray)
            }
            .padding(.top, 5)
        }
    }
}

struct BuildStepRow: View {
    let completed: Bool
    let text: String
    let duration: String
    var isPending: Bool = false
    
    var body: some View {
        HStack {
            Image(systemName: completed ? "checkmark.circle.fill" : (isPending ? "circle" : "arrow.triangle.2.circlepath"))
                .foregroundColor(completed ? .green : (isPending ? .gray.opacity(0.4) : .purple))
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(completed ? .white : (isPending ? .gray : .white.opacity(0.85)))
            
            Spacer()
            
            if !duration.isEmpty {
                Text(duration)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
    }
}

struct ReviewWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reviewing recent changes for security vulnerabilities and code quality.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(3)
            
            // Custom Code Quality Table
            VStack(spacing: 0) {
                // Table header
                HStack {
                    Text("File").foregroundColor(.gray)
                    Spacer()
                    Text("Status").foregroundColor(.gray).frame(width: 80, alignment: .leading)
                    Text("Issues").foregroundColor(.gray).frame(width: 50, alignment: .trailing)
                }
                .font(.caption)
                .bold()
                .padding(.bottom, 8)
                
                Divider().background(Color.white.opacity(0.08))
                
                VStack(spacing: 8) {
                    ReviewTableRow(file: "auth.ts", status: "Clean", statusColor: .green, statusIcon: "checkmark.circle.fill", issues: "0")
                    ReviewTableRow(file: "billing.ts", status: "Medium", statusColor: .yellow, statusIcon: "exclamationmark.triangle.fill", issues: "2", warning: true)
                    ReviewTableRow(file: "coupon.ts", status: "Clean", statusColor: .green, statusIcon: "checkmark.circle.fill", issues: "0")
                    ReviewTableRow(file: "db/schema.ts", status: "Clean", statusColor: .green, statusIcon: "checkmark.circle.fill", issues: "0")
                    ReviewTableRow(file: "api/routes.ts", status: "Low", statusColor: .yellow, statusIcon: "exclamationmark.triangle.fill", issues: "1", warning: true)
                }
                .padding(.top, 8)
            }
            .padding(10)
            .background(Color.black.opacity(0.15))
            .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Summary")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.gray)
                
                Text("• 3 issues found\n• 0 critical, 2 medium, 1 low\n• 2 files need attention")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
                    .lineSpacing(3)
            }
            
            HStack {
                Text("Analysis complete")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text("19:31")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.top, 4)
        }
    }
}

struct ReviewTableRow: View {
    let file: String
    let status: String
    let statusColor: Color
    let statusIcon: String
    let issues: String
    var warning: Bool = false
    
    var body: some View {
        HStack {
            Text(file)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.caption)
                    .foregroundColor(statusColor)
                Text(status)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
            .frame(width: 80, alignment: .leading)
            
            Text(issues)
                .font(.system(.caption, design: .monospaced))
                .bold()
                .foregroundColor(warning ? .orange : .gray)
                .frame(width: 50, alignment: .trailing)
        }
    }
}

struct WorktreeWidgetView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 15) {
            Spacer().frame(height: 10)
            
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 54, height: 54)
                
                Image(systemName: "terminal")
                    .font(.title2)
                    .foregroundColor(.purple)
            }
            
            VStack(spacing: 5) {
                Text("New worktree")
                    .font(.headline)
                    .bold()
                    .foregroundColor(.white)
                
                Text("Start a new session")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            // Keymap Shortcuts
            VStack(spacing: 8) {
                ShortcutRow(keys: ["⌘", "N"], action: "New Worktree")
                ShortcutRow(keys: ["⌘", "R"], action: "Restore Session")
                ShortcutRow(keys: ["⌘", "Q"], action: "Quit")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            
            Button(action: {}) {
                HStack(spacing: 4) {
                    Text("Learn more")
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption)
                .foregroundColor(.purple)
            }
            .buttonStyle(.plain)
            
            Spacer().frame(height: 10)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ShortcutRow: View {
    let keys: [String]
    let action: String
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(.caption, design: .monospaced))
                        .bold()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
            }
            
            Spacer()
            
            Text(action)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Main Application Layout View

struct ContentView: View {
    @StateObject var workspaceManager = WorkspaceManager()
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation
            SidebarView(workspaceManager: workspaceManager)
            
            // Right Main Work Area
            VStack(spacing: 0) {
                // Header bar
                ToolbarView(workspaceManager: workspaceManager)
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                // Active workspace panes grid
                GridContainerView(workspaceManager: workspaceManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .foregroundColor(.white)
    }
}

// MARK: - macOS App Main entrypoint

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            
            // Premium feature: make background draggable so window can be dragged from empty areas
            window.isMovableByWindowBackground = true
            
            // Set beautiful starting size
            window.setFrame(NSRect(x: 100, y: 100, width: 1360, height: 840), display: true)
            window.minSize = NSSize(width: 1024, height: 680)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct MyTerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                // True macOS desktop glassmorphism
                .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        }
        .windowStyle(.hiddenTitleBar)
    }
}
