import AppKit
import MyTermCore
import SwiftUI

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
        .shadow: shadow,
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
    private var keyMonitor: Any?

    @objc func newTerminal() { NotificationCenter.default.post(name: AppNotification.newTerminal, object: nil) }
    @objc func closeTerminal() {
        if TerminalRegistry.shared.terminalFirstResponder(in: window) != nil {
            NotificationCenter.default.post(name: AppNotification.closeTerminal, object: nil)
        } else {
            window?.performClose(nil)
        }
    }
    @objc func openCodexDesktop() { NotificationCenter.default.post(name: AppNotification.openCodexDesktop, object: nil) }
    @objc func newLocalCodexTerminal() {
        NotificationCenter.default.post(name: AppNotification.runAgentPreset, object: AgentPreset.localCodex.rawValue)
    }
    @objc func newGoogleAntigravityTerminal() {
        NotificationCenter.default.post(name: AppNotification.runAgentPreset, object: AgentPreset.googleAntigravity.rawValue)
    }
    @objc func restorePreviousSession() { NotificationCenter.default.post(name: AppNotification.restoreSessions, object: nil) }
    @objc func runSetupAgain() { WorkspaceManager.shared?.runSetupAgain() }

    func applicationWillTerminate(_ notification: Notification) {
        WorkspaceManager.shared?.saveSessionState()
        WorkspaceManager.shared?.plannerStore.saveNow()
        TerminalRegistry.shared.terminateAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchSignpost = PerformanceTelemetry.begin("Application Launch")
        defer { PerformanceTelemetry.end("Application Launch", id: launchSignpost) }
        setupMenu()

        if let iconImage = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = iconImage
        } else {
            NSApp.applicationIconImage = generateAppIcon()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let hasOption = event.modifierFlags.contains(.option)
            let hasCmd = event.modifierFlags.contains(.command)
            let hasControl = event.modifierFlags.contains(.control)
            let hasShift = event.modifierFlags.contains(.shift)

            if hasCmd && !hasOption && !hasControl && !hasShift,
                (event.charactersIgnoringModifiers == "\u{7F}" || event.keyCode == 51),
                TerminalRegistry.shared.terminalFirstResponder(in: event.window) != nil
            {
                NotificationCenter.default.post(name: AppNotification.clearTerminalInput, object: nil)
                return nil
            }

            // Cmd + V for Clipboard Image/File Handling before standard text paste can consume it
            if hasCmd && !hasOption && !hasControl && !hasShift,
                event.charactersIgnoringModifiers == "v",
                TerminalRegistry.shared.terminalFirstResponder(in: event.window) != nil
            {
                let pasteboard = NSPasteboard.general
                let hasFile = pasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
                let hasImage =
                    pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
                    || pasteboard.types?.contains(.png) == true
                    || pasteboard.types?.contains(.tiff) == true
                let hasPlainText = pasteboard.string(forType: .string)?.isEmpty == false

                if hasFile || (hasImage && !hasPlainText) {
                    NotificationCenter.default.post(name: AppNotification.pasteImage, object: nil)
                    return nil
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

        window.allowsConcurrentViewDrawing = false
        window.colorSpace = NSColorSpace.sRGB
        window.sharingType = .readWrite

        let hostingView = NSHostingView(
            rootView: ContentView()
                .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                .clipShape(RoundedRectangle(cornerRadius: 18))  // Rounded corners like standard macOS apps
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .ignoresSafeArea()
        )
        hostingView.wantsLayer = true
        hostingView.layer?.drawsAsynchronously = false
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
        let quitItem = NSMenuItem(
            title: "Quit \(MyTermIdentity.productName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(NSMenuItem(title: "Setup and Access…", action: #selector(AppDelegate.runSetupAgain), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(quitItem)

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        // Cmd + T
        let newItem = NSMenuItem(title: "New Terminal", action: #selector(AppDelegate.newTerminal), keyEquivalent: "t")
        fileMenu.addItem(newItem)

        // Cmd + Shift + T
        let restoreItem = NSMenuItem(
            title: "Restore Previous Session", action: #selector(AppDelegate.restorePreviousSession), keyEquivalent: "t")
        restoreItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(restoreItem)

        let openCodexItem = NSMenuItem(
            title: "Open Workspace in Codex Desktop", action: #selector(AppDelegate.openCodexDesktop), keyEquivalent: "o")
        openCodexItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(openCodexItem)

        let localCodexItem = NSMenuItem(
            title: "New Local Codex Terminal (Not Phone-Synced)", action: #selector(AppDelegate.newLocalCodexTerminal), keyEquivalent: "l")
        localCodexItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(localCodexItem)

        let googleAntigravityItem = NSMenuItem(
            title: "New Google Antigravity Tab", action: #selector(AppDelegate.newGoogleAntigravityTerminal), keyEquivalent: "g")
        googleAntigravityItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(googleAntigravityItem)

        // Cmd + W
        let closeItem = NSMenuItem(title: "Close Terminal or Window", action: #selector(AppDelegate.closeTerminal), keyEquivalent: "w")
        closeItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(closeItem)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return true }
}
