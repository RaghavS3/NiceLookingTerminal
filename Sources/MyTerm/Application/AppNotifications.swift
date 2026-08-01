import Foundation

enum AppNotification {
    static let newTerminal = Notification.Name("NewTerminal")
    static let closeTerminal = Notification.Name("CloseTerminal")
    static let restoreSessions = Notification.Name("RestoreSessions")
    static let runAgentPreset = Notification.Name("RunAgentPreset")
    static let openCodexAgent = Notification.Name("OpenCodexAgent")
    static let clearTerminalInput = Notification.Name("ClearTerminalInput")
    static let pasteImage = Notification.Name("PasteImage")
}
