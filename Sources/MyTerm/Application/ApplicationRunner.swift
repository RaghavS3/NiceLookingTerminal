import AppKit

public func runNiceLookingTerminalApplication() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
