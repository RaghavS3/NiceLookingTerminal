import AppKit
import MyTermCore
import SwiftUI

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
                        PlannerWorkspaceView(store: workspaceManager.plannerStore)
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
        .onReceive(NotificationCenter.default.publisher(for: AppNotification.newTerminal)) { _ in
            if workspaceManager.mode == .terminals {
                workspaceManager.addSession()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppNotification.closeTerminal)) { _ in
            if workspaceManager.mode == .terminals {
                workspaceManager.removeActiveSession()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppNotification.restoreSessions)) { _ in
            if workspaceManager.mode == .terminals {
                workspaceManager.restoreSessions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppNotification.runAgentPreset)) { notification in
            guard let rawValue = notification.object as? String, let preset = AgentPreset(rawValue: rawValue) else {
                return
            }
            workspaceManager.runPreset(preset)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppNotification.openCodexAgent)) { _ in
            workspaceManager.openCodexAgent()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppNotification.clearTerminalInput)) { _ in
            if workspaceManager.mode == .terminals {
                workspaceManager.clearActiveInput()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppNotification.pasteImage)) { _ in
            workspaceManager.handleClipboardImage()
        }
        .alert(
            "Launch failed",
            isPresented: Binding(
                get: { workspaceManager.launchError != nil },
                set: { if !$0 { workspaceManager.launchError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { workspaceManager.launchError = nil }
        } message: {
            Text(workspaceManager.launchError ?? "Unknown error")
        }
        .sheet(isPresented: $workspaceManager.isShowingSetup) {
            OnboardingView(manager: workspaceManager)
        }
    }
}
