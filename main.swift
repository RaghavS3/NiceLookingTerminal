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
        
        let pid = forkpty(&master, nil, nil, &size)
        if pid < 0 {
            print("[PTYError] forkpty failed")
            return
        }
        
        if pid == 0 {
            // Child process: launch shell
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
            exit(1)
        } else {
            self.masterFD = master
            self.childPID = pid
            
            fcntl(master, F_SETFL, O_NONBLOCK)
            
            let queue = DispatchQueue(label: "com.myterm.pty.read-\(UUID().uuidString)")
            let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
            
            source.setEventHandler { [weak self] in
                guard let self = self else { return }
                var buffer = [UInt8](repeating: 0, count: 8192)
                let bytesRead = Darwin.read(self.masterFD, &buffer, buffer.count)
                
                if bytesRead > 0 {
                    let data = Data(bytes: buffer, count: bytesRead)
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

// MARK: - Core Terminal Session State

class TerminalSession: ObservableObject, Identifiable {
    let id = UUID()
    var ptySession: PTYSession?
    var onDataReceived: ((String) -> Void)?
    
    init() {
        self.ptySession = PTYSession(onData: { [weak self] base64String in
            self?.onDataReceived?(base64String)
        })
    }
    
    deinit {
        ptySession?.stop()
    }
}

// MARK: - WebKit xterm.js Terminal Renderer

struct TerminalWebView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        
        contentController.add(context.coordinator, name: "terminalInput")
        contentController.add(context.coordinator, name: "terminalResize")
        
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // Transparent WebView backing
        webView.setValue(false, forKey: "drawsBackground")
        
        let html = getTerminalHTML()
        webView.loadHTMLString(html, baseURL: URL(string: "https://localhost"))
        
        context.coordinator.webView = webView
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: TerminalWebView
        var webView: WKWebView?
        
        init(_ parent: TerminalWebView) {
            self.parent = parent
            super.init()
            
            parent.session.onDataReceived = { [weak self] base64String in
                self?.writeToTerminal(base64: base64String)
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "terminalInput", let input = message.body as? String {
                parent.session.ptySession?.write(input)
            } else if message.name == "terminalResize", let dict = message.body as? [String: Int] {
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
                padding: 12px;
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
                fontSize: 12.5,
                rows: 30,
                cols: 80
            });
            
            term.open(document.getElementById('terminal-container'));
            
            term.onData(data => {
                window.webkit.messageHandlers.terminalInput.postMessage(data);
            });
            
            function writeBase64(base64) {
                try {
                    const raw = atob(base64);
                    term.write(raw);
                } catch(e) {
                    console.error("Base64 write error", e);
                }
            }
            
            function reportResize() {
                const cols = Math.floor((window.innerWidth - 24) / 7.5);
                const rows = Math.floor((window.innerHeight - 24) / 15.0);
                if (cols > 0 && rows > 0) {
                    term.resize(cols, rows);
                    window.webkit.messageHandlers.terminalResize.postMessage({ cols, rows });
                }
            }
            
            window.addEventListener('resize', reportResize);
            setTimeout(reportResize, 150);
        </script>
    </body>
    </html>
    """
}

// MARK: - Visual Effect (Desktop Vibrancy Backdrop)

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

// MARK: - Minimalist Glassmorphic Pane Container

struct GlassCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(Color.black.opacity(0.28))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

struct PaneView: View {
    @ObservedObject var session: TerminalSession
    
    var body: some View {
        GlassCard {
            TerminalWebView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Clean Resizable Grid Split Controller

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
        // Maintain up to 6 PTY instances, cleanly mapped
        self.sessions = [
            TerminalSession(),
            TerminalSession(),
            TerminalSession(),
            TerminalSession(),
            TerminalSession(),
            TerminalSession()
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
                        .padding(14)
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
                .padding(14)
                
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
                .padding(14)
                
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
                .padding(14)
                
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
                .padding(14)
            }
        }
    }
}

// MARK: - Floating Dynamic Capsule Layout Controls

struct FloatingLayoutSwitcher: View {
    @ObservedObject var workspaceManager: WorkspaceManager
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            LayoutCapsuleButton(icon: "square", active: workspaceManager.currentLayout == .single) {
                workspaceManager.currentLayout = .single
            }
            LayoutCapsuleButton(icon: "square.split.2x1", active: workspaceManager.currentLayout == .doubleHorizontal) {
                workspaceManager.currentLayout = .doubleHorizontal
            }
            LayoutCapsuleButton(icon: "square.split.1x2", active: workspaceManager.currentLayout == .doubleVertical) {
                workspaceManager.currentLayout = .doubleVertical
            }
            LayoutCapsuleButton(icon: "square.split.2x2", active: workspaceManager.currentLayout == .quad) {
                workspaceManager.currentLayout = .quad
            }
            LayoutCapsuleButton(icon: "rectangle.grid.3x2", active: workspaceManager.currentLayout == .hex) {
                workspaceManager.currentLayout = .hex
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.4))
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .opacity(isHovered ? 1.0 : 0.35)
        .animation(.easeInOut(duration: 0.25), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct LayoutCapsuleButton: View {
    let icon: String
    let active: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(active ? .purple : .gray.opacity(0.8))
                .scaleEffect(active ? 1.1 : 1.0)
                .animation(.spring(), value: active)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main Application View Layout

struct ContentView: View {
    @StateObject var workspaceManager = WorkspaceManager()
    
    var body: some View {
        ZStack(alignment: .top) {
            // Edge-to-edge resizable PTY shell splits
            GridContainerView(workspaceManager: workspaceManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Ultra-minimal floating Dynamic Island layout switcher at the top center
            FloatingLayoutSwitcher(workspaceManager: workspaceManager)
                .padding(.top, 25)
        }
        .preferredColorScheme(.dark)
        .foregroundColor(.white)
    }
}

// MARK: - macOS App Entrypoint

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            
            // Allow dragging the entire window from any background space
            window.isMovableByWindowBackground = true
            
            // Set starting bounds
            window.setFrame(NSRect(x: 100, y: 100, width: 1360, height: 840), display: true)
            window.minSize = NSSize(width: 800, height: 500)
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
                .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        }
        .windowStyle(.hiddenTitleBar)
    }
}
