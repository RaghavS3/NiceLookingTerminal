import SwiftUI
import AppKit
import WebKit
import Foundation
import Combine
import Darwin

// MARK: - POSIX Pseudo-Terminal Session (Real Shell Integration)

class PTYSession {
    var masterFD: Int32 = -1
    var childPID: pid_t = -1
    var readSource: DispatchSourceRead?
    var onData: ((String) -> Void)?
    
    init(onData: @escaping (String) -> Void) {
        self.onData = onData
        start()
    }
    
    func start() {
        var master: Int32 = 0
        var size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        
        // Spawn a low-level pseudo-terminal and fork the process
        let pid = forkpty(&master, nil, nil, &size)
        if pid < 0 {
            print("[PTYError] forkpty failed")
            return
        }
        
        if pid == 0 {
            // Child process: configure terminal environment and execute system Zsh
            setenv("TERM", "xterm-256color", 1)
            setenv("LANG", "en_US.UTF-8", 1)
            
            let shell = "/bin/zsh"
            let args = ["--login"]
            
            let cShell = shell.cString(using: .utf8)!
            let cArgs = args.map { $0.cString(using: .utf8)! }
            
            var argv: [UnsafeMutablePointer<CChar>?] = []
            argv.append(UnsafeMutablePointer(mutating: cShell))
            for arg in cArgs {
                argv.append(UnsafeMutablePointer(mutating: arg))
            }
            argv.append(nil)
            
            execvp(shell, &argv)
            exit(1) // Exec failed
        } else {
            // Parent process: keep master file descriptor and start background reading
            self.masterFD = master
            self.childPID = pid
            
            // Set file descriptor to non-blocking read state
            fcntl(master, F_SETFL, O_NONBLOCK)
            
            let queue = DispatchQueue(label: "com.myterm.pty.read-\(UUID().uuidString)")
            let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
            
            source.setEventHandler { [weak self] in
                guard let self = self else { return }
                var buffer = [UInt8](repeating: 0, count: 8192)
                let bytesRead = Darwin.read(self.masterFD, &buffer, buffer.count)
                
                if bytesRead > 0 {
                    let data = Data(bytes: buffer, count: bytesRead)
                    // Encode data as Base64 to safely bridge binary and UTF-8 shell characters to JS
                    let base64String = data.base64EncodedString()
                    DispatchQueue.main.async {
                        self.onData?(base64String)
                    }
                } else if bytesRead < 0 {
                    let err = errno
                    if err != EAGAIN && err != EINTR {
                        self.stop()
                    }
                } else {
                    // EOF
                    self.stop()
                }
            }
            
            source.setCancelHandler { [weak self] in
                guard let self = self else { return }
                Darwin.close(self.masterFD)
            }
            
            self.readSource = source
            source.resume()
        }
    }
    
    func write(_ string: String) {
        guard masterFD >= 0 else { return }
        if let data = string.data(using: .utf8) {
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                if let baseAddress = bytes.baseAddress {
                    let _ = Darwin.write(self.masterFD, baseAddress, data.count)
                }
            }
        }
    }
    
    func resize(cols: Int, rows: Int) {
        guard masterFD >= 0 else { return }
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        let _ = ioctl(masterFD, UInt(TIOCSWINSZ), &size)
    }
    
    func stop() {
        readSource?.cancel()
        readSource = nil
        masterFD = -1
        if childPID > 0 {
            kill(childPID, SIGKILL)
            childPID = -1
        }
    }
    
    deinit {
        stop()
    }
}

// MARK: - Models and States

class TerminalSession: ObservableObject, Identifiable {
    let id = UUID()
    let index: String
    @Published var name: String
    @Published var path: String = "~/projects/nebula"
    @Published var tag: String = "idle"
    @Published var tagColor: Color = .gray
    
    // View Modes: "dashboard" (gorgeous visualization cards) or "terminal" (REAL Zsh shell terminal itself!)
    @Published var viewMode: String = "terminal"
    @Published var widgetType: String = "none" // Widget dashboard preset
    
    // PTY session reference
    var ptySession: PTYSession?
    
    // Hook callback for transparent Cocoa WKWebView instance
    var onDataReceived: ((String) -> Void)?
    
    init(index: String, name: String, tag: String = "idle", tagColor: Color = .gray, widgetType: String = "none", viewMode: String = "terminal") {
        self.index = index
        self.name = name
        self.tag = tag
        self.tagColor = tagColor
        self.widgetType = widgetType
        self.viewMode = viewMode
        
        // Spawn active background PTY shell immediately
        self.ptySession = PTYSession(onData: { [weak self] base64String in
            self?.onDataReceived?(base64String)
        })
    }
    
    deinit {
        ptySession?.stop()
    }
}

// MARK: - Transparent Cocoa WebView Terminal Renderer (xterm.js embed)

struct TerminalWebView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        
        // Handle input events and terminal size reports dynamically from JavaScript
        contentController.add(context.coordinator, name: "terminalInput")
        contentController.add(context.coordinator, name: "terminalResize")
        
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // Premium feature: make the web view background completely transparent
        webView.setValue(false, forKey: "drawsBackground")
        
        // Assemble and load the local inline HTML container
        let html = getTerminalHTML()
        webView.loadHTMLString(html, baseURL: URL(string: "https://localhost"))
        
        context.coordinator.webView = webView
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // PTY session reference update if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: TerminalWebView
        var webView: WKWebView?
        
        init(_ parent: TerminalWebView) {
            self.parent = parent
            super.init()
            
            // Link raw data listener callback from POSIX PTY directly into the WebView renderer
            parent.session.onDataReceived = { [weak self] base64String in
                self?.writeToTerminal(base64: base64String)
            }
        }
        
        // Receive messages from JS
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "terminalInput", let input = message.body as? String {
                // Write keyboard keystrokes instantly to POSIX shell standard input
                parent.session.ptySession?.write(input)
            } else if message.name == "terminalResize", let dict = message.body as? [String: Int] {
                // Keep the POSIX process pty window size in sync when dividers are resized by user
                if let cols = dict["cols"], let rows = dict["rows"] {
                    parent.session.ptySession?.resize(cols: cols, rows: rows)
                }
            }
        }
        
        func writeToTerminal(base64: String) {
            let js = "writeBase64('\(base64)');"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

// MARK: - Transparent Terminal HTML Template with xterm.js

func getTerminalHTML() -> String {
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css" />
        <script src="https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.js"></script>
        <style>
            html, body {
                margin: 0;
                padding: 0;
                width: 100%;
                height: 100%;
                background: transparent !important;
                overflow: hidden;
            }
            #terminal-container {
                width: 100%;
                height: 100%;
                background: transparent !important;
                padding: 10px;
                box-sizing: border-box;
            }
            .xterm .xterm-viewport {
                background-color: transparent !important;
            }
            .xterm-screen {
                background-color: transparent !important;
            }
        </style>
    </head>
    <body>
        <div id="terminal-container"></div>
        <script>
            // Configure premium xterm renderer with a transparent visual backing and neon themes
            const term = new Terminal({
                allowProposedApi: true,
                theme: {
                    background: 'transparent',
                    foreground: '#ffffff',
                    cursor: '#a855f7',
                    selectionBackground: 'rgba(168, 85, 247, 0.3)',
                    black: '#000000',
                    red: '#ef4444',
                    green: '#22c55e',
                    yellow: '#eab308',
                    blue: '#3b82f6',
                    magenta: '#a855f7',
                    cyan: '#06b6d4',
                    white: '#ffffff',
                },
                cursorBlink: true,
                fontFamily: 'Menlo, Monaco, "Courier New", monospace',
                fontSize: 12,
                rows: 30,
                cols: 80
            });
            
            term.open(document.getElementById('terminal-container'));
            
            // Forward keystrokes directly to Swift message dispatcher
            term.onData(data => {
                window.webkit.messageHandlers.terminalInput.postMessage(data);
            });
            
            // Safely write base64 strings decoded to binary
            function writeBase64(base64) {
                try {
                    const raw = atob(base64);
                    term.write(raw);
                } catch(e) {
                    console.error("Base64 write error", e);
                }
            }
            
            // Report responsive bounds changes dynamically
            function reportResize() {
                const cols = Math.floor((window.innerWidth - 20) / 7.2); // width of a char
                const rows = Math.floor((window.innerHeight - 20) / 14.5); // height of a char
                if (cols > 0 && rows > 0) {
                    term.resize(cols, rows);
                    window.webkit.messageHandlers.terminalResize.postMessage({ cols, rows });
                }
            }
            
            window.addEventListener('resize', reportResize);
            // Wait slightly for container rendering
            setTimeout(reportResize, 150);
        </script>
    </body>
    </html>
    """
}

// MARK: - Visual Effect (Glassmorphism Backdrop)

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

// MARK: - Premium Glassmorphic Card Container

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
                
                // Toggle mode selector: Tab switcher between beautiful widgets and REAL shells
                HStack(spacing: 0) {
                    Button(action: { session.viewMode = "dashboard" }) {
                        Text("Widget")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(session.viewMode == "dashboard" ? Color.white.opacity(0.12) : Color.clear)
                            .foregroundColor(session.viewMode == "dashboard" ? .white : .gray)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { session.viewMode = "terminal" }) {
                        Text("Terminal")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(session.viewMode == "terminal" ? Color.white.opacity(0.12) : Color.clear)
                            .foregroundColor(session.viewMode == "terminal" ? .white : .gray)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
                .background(Color.black.opacity(0.25))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.trailing, 5)
                
                // State Tag Pill
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
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.02))
            
            Divider()
                .background(Color.white.opacity(0.06))
            
            // Main card frame contents
            ZStack {
                if session.viewMode == "terminal" {
                    // 100% REAL Shell Pseudo-Terminal!
                    TerminalWebView(session: session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Gorgeous visual AI/Build dashboard widget!
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if session.widgetType == "planning" {
                                PlanningWidgetView()
                            } else if session.widgetType == "audit" {
                                AuditWidgetView()
                            } else if session.widgetType == "explore" {
                                ExploreWidgetView()
                            } else if session.widgetType == "build" {
                                BuildWidgetView()
                            } else if session.widgetType == "review" {
                                ReviewWidgetView()
                            } else if session.widgetType == "worktree" {
                                WorktreeWidgetView()
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
            // Start sessions 1, 2, 4, 5 in Dashboard preset widgets, and sessions 3, 6 in fully-active terminal shells!
            TerminalSession(index: "01", name: "Planning", tag: "plan", tagColor: .purple, widgetType: "planning", viewMode: "dashboard"),
            TerminalSession(index: "02", name: "Audit", tag: "audit", tagColor: .blue, widgetType: "audit", viewMode: "dashboard"),
            TerminalSession(index: "03", name: "Explore", tag: "explore", tagColor: .green, widgetType: "explore", viewMode: "terminal"),
            TerminalSession(index: "04", name: "Build", tag: "build", tagColor: .purple, widgetType: "build", viewMode: "dashboard"),
            TerminalSession(index: "05", name: "Review", tag: "review", tagColor: .purple, widgetType: "review", viewMode: "dashboard"),
            TerminalSession(index: "06", name: "Worktree", tag: "idle", tagColor: .gray, widgetType: "worktree", viewMode: "terminal")
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

// MARK: - GUI Dashboard Widgets (Rich Output UI presets)

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
            
            VStack(alignment: .leading, spacing: 8) {
                BuildStepRow(completed: true, text: "Install dependencies", duration: "1.2s")
                BuildStepRow(completed: true, text: "Type check", duration: "2.8s")
                BuildStepRow(completed: true, text: "Build production bundle", duration: "5.6s")
                BuildStepRow(completed: false, text: "Run tests", duration: "", isPending: true)
                BuildStepRow(completed: false, text: "Upload artifacts", duration: "", isPending: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            
            // Progress Bar
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
                            .frame(width: geo.size.width * 0.68, height: 6)
                    }
                }
                .frame(height: 6)
                
                Text("68%")
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
            
            // Custom Table
            VStack(spacing: 0) {
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
                
                // Active workspace resizable grid
                GridContainerView(workspaceManager: workspaceManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .foregroundColor(.white)
    }
}

// MARK: - macOS App Main Entrypoint

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            
            // Make background draggable so window can be dragged from empty areas
            window.isMovableByWindowBackground = true
            
            // Set starting size
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
