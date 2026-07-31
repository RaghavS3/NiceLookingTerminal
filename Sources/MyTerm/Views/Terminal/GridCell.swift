import SwiftUI

struct GridCell: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject var manager: WorkspaceManager
    @State private var isHovered = false
    @State private var showTitleEditor = false
    @State private var tempTitle = ""
    @State private var showDeleteTranscriptConfirmation = false

    var isActive: Bool { manager.activeSessionID == session.id }
    var isMaximized: Bool { manager.maximizedSessionID == session.id }

    var body: some View {
        ZStack {
            // Flush terminal layout spanning 100% of cell
            TerminalCellView(session: session)
                .padding(8)

            inactiveOverlay

            hoverControls

            processStatus

            if session.hasUnseenOutput {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button("New output") {
                            TerminalRegistry.shared.jumpToLatest(for: session.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(12)
                    }
                }
            }

            titleEditor
        }
        .background(cellBackground)
        .overlay(cellStrokeOverlayActive)
        .overlay(cellStrokeOverlayInactive)
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            manager.handleDroppedProviders(providers, onSessionID: session.id)
            return true
        }
        .shadow(color: isActive ? Color.white.opacity(0.02) : Color.clear, radius: 4, x: 0, y: 1)
        .cornerRadius(18)
        .onHover { hovering in
            // Fast hover response without spring bounce
            isHovered = hovering
        }
        .contextMenu {
            Button("Open Searchable Transcript") { TerminalRegistry.shared.openTranscript(for: session.id) }
            Button("Reveal Transcript Folder") { TerminalRegistry.shared.revealTranscript(for: session.id) }
            Button("Export Transcript…") { TerminalRegistry.shared.exportTranscript(for: session.id) }
            Divider()
            Button("Delete Transcript…", role: .destructive) { showDeleteTranscriptConfirmation = true }
        }
        .confirmationDialog(
            "Delete this terminal’s recorded history?",
            isPresented: $showDeleteTranscriptConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Transcript", role: .destructive) {
                TerminalRegistry.shared.deleteTranscript(for: session.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The live terminal stays open and recording restarts in a new empty transcript.")
        }
    }

    @ViewBuilder
    private var processStatus: some View {
        if let status = processStatusPresentation {
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Text(status.message)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    if status.canRestart {
                        Button("Restart") { TerminalRegistry.shared.restart(session) }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
    }

    private var processStatusPresentation: (message: String, canRestart: Bool)? {
        switch session.processState {
        case .starting:
            return ("Starting…", false)
        case .running:
            return nil
        case .exited(let exitCode):
            return (exitCode.map { "Exited (\($0))" } ?? "Exited", true)
        case .failed(let message):
            return (message, true)
        case .disconnected:
            return ("Disconnected", true)
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
        .allowsHitTesting(!isActive)  // If active, the entire ZStack doesn't intercept hits
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
                                TerminalRegistry.shared.openTranscript(for: session.id)
                            }) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Open searchable transcript")
                            .accessibilityLabel("Open searchable transcript")

                            Button(action: {
                                tempTitle = session.title
                                showTitleEditor = true
                            }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Rename terminal")
                            .accessibilityLabel("Rename terminal")

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
                            .help(isMaximized ? "Restore terminal grid" : "Maximize terminal")
                            .accessibilityLabel(isMaximized ? "Restore terminal grid" : "Maximize terminal")

                            Button(action: {
                                manager.removeSession(session)
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                            .help("Close terminal")
                            .accessibilityLabel("Close terminal")
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

                    TextField(
                        "e.g. Server, Logs...", text: $tempTitle,
                        onCommit: {
                            session.title = tempTitle
                            showTitleEditor = false
                            WorkspaceManager.shared?.scheduleSessionStateSave()
                        }
                    )
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
                            WorkspaceManager.shared?.scheduleSessionStateSave()
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
                LinearGradient(
                    colors: [Color.white.opacity(isActive ? 0.35 : 0.0), Color.white.opacity(isActive ? 0.12 : 0.0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: isActive ? 1.5 : 0
            )
    }

    @ViewBuilder
    private var cellStrokeOverlayInactive: some View {
        RoundedRectangle(cornerRadius: 18)
            .stroke(Color.white.opacity(isActive ? 0.0 : 0.05), lineWidth: 1)
    }
}
