import SwiftUI
import AppKit
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

// MARK: - Native High-Performance Terminal Stream Buffer

class TerminalBuffer: ObservableObject {
    @Published var lines: [String] = [""]
    
    func append(_ text: String) {
        var currentLine = lines.last ?? ""
        
        var i = text.startIndex
        while i < text.endIndex {
            let char = text[i]
            
            if char == "\n" {
                lines[lines.count - 1] = currentLine
                lines.append("")
                currentLine = ""
            } else if char == "\r" {
                // Return to start of current line
                currentLine = ""
            } else if char == "\u{08}" || char == "\u{7F}" {
                // Backspace: remove last character
                if !currentLine.isEmpty {
                    currentLine.removeLast()
                }
            } else if char == "\u{001B}" {
                // ANSI Escape sequence parser: skip ANSI controls to render clean terminal output
                var j = text.index(after: i)
                while j < text.endIndex {
                    let ec = text[j]
                    if (ec >= "A" && ec <= "Z") || (ec >= "a" && ec <= "z") {
                        i = j
                        break
                    }
                    j = text.index(after: j)
                }
            } else {
                currentLine.append(char)
            }
            
            if i < text.endIndex {
                i = text.index(after: i)
            }
        }
        
        lines[lines.count - 1] = currentLine
        
        // Limit scrollback to last 400 lines for maximum speed
        if lines.count > 400 {
            lines.removeFirst(lines.count - 400)
        }
    }
}

// MARK: - Core Terminal Session State

class TerminalSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published var terminalBuffer = TerminalBuffer()
    var ptySession: PTYSession?
    
    init() {
        self.ptySession = PTYSession(onData: { [weak self] base64String in
            if let data = Data(base64Encoded: base64String) {
                let text = String(decoding: data, as: UTF8.self)
                DispatchQueue.main.async {
                    self?.terminalBuffer.append(text)
                }
            }
        })
    }
    
    deinit {
        ptySession?.stop()
    }
}

// MARK: - Native Keyboard Capture Input View (AppKit -> SwiftUI)

struct NativeKeyboardInputView: NSViewRepresentable {
    let onInput: (String) -> Void
    @Binding var isFocused: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyboardCaptureNSView()
        view.onInput = onInput
        view.onFocusChange = { focused in
            DispatchQueue.main.async {
                self.isFocused = focused
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class KeyboardCaptureNSView: NSView {
    var onInput: ((String) -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        onFocusChange?(true)
        return super.becomeFirstResponder()
    }
    
    override func resignFirstResponder() -> Bool {
        onFocusChange?(false)
        return super.resignFirstResponder()
    }
    
    override func keyDown(with event: NSEvent) {
        // Map native keyboard codes for system shells
        if event.keyCode == 126 { // Arrow Up
            onInput?("\u{1B}[A")
            return
        } else if event.keyCode == 125 { // Arrow Down
            onInput?("\u{1B}[B")
            return
        } else if event.keyCode == 124 { // Arrow Right
            onInput?("\u{1B}[C")
            return
        } else if event.keyCode == 123 { // Arrow Left
            onInput?("\u{1B}[D")
            return
        }
        
        switch event.keyCode {
        case 36: // Enter
            onInput?("\r")
        case 48: // Tab
            onInput?("\t")
        case 51: // Backspace
            onInput?("\u{7F}")
        case 53: // Escape
            onInput?("\u{1B}")
        default:
            if let chars = event.characters {
                onInput?(chars)
            } else {
                super.keyDown(with: event)
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        // Click focuses this cell immediately
        self.window?.makeFirstResponder(self)
    }
}

// MARK: - Native SwiftUI Terminal Rendering View

struct NativeTerminalView: View {
    @ObservedObject var session: TerminalSession
    @State private var isFocused = false
    
    var body: some View {
        ZStack {
            // Invisible, transparent responder that catches keystrokes
            NativeKeyboardInputView(onInput: { chars in
                session.ptySession?.write(chars)
            }, isFocused: $isFocused)
            
            // Highly optimized native lines list view
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(0..<session.terminalBuffer.lines.count, id: \.self) { index in
                            Text(session.terminalBuffer.lines[index])
                                .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(12)
                }
                .onChange(of: session.terminalBuffer.lines.count) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .background(isFocused ? Color.purple.opacity(0.04) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isFocused ? Color.purple.opacity(0.45) : Color.white.opacity(0.08), lineWidth: isFocused ? 1.5 : 1)
        )
        .cornerRadius(16)
    }
}

// MARK: - Desktop Vibrancy Backdrop

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
                    NativeTerminalView(session: workspaceManager.sessions[0])
                        .padding(14)
                }
                
            case .doubleHorizontal:
                HSplitView {
                    if workspaceManager.sessions.count > 0 {
                        NativeTerminalView(session: workspaceManager.sessions[0])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if workspaceManager.sessions.count > 1 {
                        NativeTerminalView(session: workspaceManager.sessions[1])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(14)
                
            case .doubleVertical:
                VSplitView {
                    if workspaceManager.sessions.count > 0 {
                        NativeTerminalView(session: workspaceManager.sessions[0])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if workspaceManager.sessions.count > 1 {
                        NativeTerminalView(session: workspaceManager.sessions[1])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(14)
                
            case .quad:
                HSplitView {
                    VSplitView {
                        if workspaceManager.sessions.count > 0 {
                            NativeTerminalView(session: workspaceManager.sessions[0])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if workspaceManager.sessions.count > 1 {
                            NativeTerminalView(session: workspaceManager.sessions[1])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    VSplitView {
                        if workspaceManager.sessions.count > 2 {
                            NativeTerminalView(session: workspaceManager.sessions[2])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if workspaceManager.sessions.count > 3 {
                            NativeTerminalView(session: workspaceManager.sessions[3])
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
                            NativeTerminalView(session: workspaceManager.sessions[0])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if workspaceManager.sessions.count > 3 {
                            NativeTerminalView(session: workspaceManager.sessions[3])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    VSplitView {
                        if workspaceManager.sessions.count > 1 {
                            NativeTerminalView(session: workspaceManager.sessions[1])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if workspaceManager.sessions.count > 4 {
                            NativeTerminalView(session: workspaceManager.sessions[4])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    VSplitView {
                        if workspaceManager.sessions.count > 2 {
                            NativeTerminalView(session: workspaceManager.sessions[2])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if workspaceManager.sessions.count > 5 {
                            NativeTerminalView(session: workspaceManager.sessions[5])
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
            // Streamlined, resizable terminal splits
            GridContainerView(workspaceManager: workspaceManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Layout pill controls at the top center
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
            
            window.isMovableByWindowBackground = true
            
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
