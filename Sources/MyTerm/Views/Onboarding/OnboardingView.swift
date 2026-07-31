import MyTermCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var manager: WorkspaceManager
    @State private var cleanupRequest: CleanupRequest?

    private enum CleanupRequest {
        case attachments
        case transcripts

        var title: String {
            switch self {
            case .attachments: return "Delete all copied attachments?"
            case .transcripts: return "Delete history for closed terminals?"
            }
        }

        var actionTitle: String {
            switch self {
            case .attachments: return "Delete Copied Attachments"
            case .transcripts: return "Delete Inactive Transcripts"
            }
        }

        var message: String {
            switch self {
            case .attachments: return "This removes only app-owned attachment copies. Original files are not touched."
            case .transcripts: return "Transcripts belonging to terminals that are still open are preserved."
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set up NiceLookingTerminal")
                    .font(.system(size: 24, weight: .semibold))
                Text("Choose one workspace and one access profile. You can change both later.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    setupSection(number: "1", title: "Workspace") {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(manager.selectedWorkspaceURL.lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                Text(manager.selectedWorkspaceURL.path)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button("Choose…") { manager.chooseWorkspace() }
                        }
                    }

                    Divider().padding(.vertical, 18)

                    setupSection(number: "2", title: "Agent access") {
                        Picker(
                            "Agent access",
                            selection: Binding(
                                get: { manager.preferences.accessMode },
                                set: { manager.setAccessMode($0) }
                            )
                        ) {
                            Text("Standard").tag(AgentAccessMode.standard)
                            Text("Full Agent Access").tag(AgentAccessMode.full)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        if manager.preferences.accessMode == .full {
                            Text(
                                "Local agents start with their documented skip-permission mode. macOS still requires one manual Full Disk Access approval; apps cannot grant that permission to themselves."
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                            HStack {
                                Button("Open Full Disk Access Settings") {
                                    manager.openFullDiskAccessSettings()
                                }
                                Button("Check access") { manager.verifyAccess() }
                                Spacer()
                            }

                            if !manager.accessChecks.isEmpty {
                                HStack(spacing: 14) {
                                    ForEach(manager.accessChecks) { check in
                                        Label(
                                            check.label,
                                            systemImage: check.isReadable ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                                        )
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(check.isReadable ? Color.green : Color.orange)
                                        .help(check.path)
                                    }
                                    Label(
                                        "Network",
                                        systemImage: manager.isNetworkAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                                    )
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(manager.isNetworkAvailable ? Color.green : Color.orange)
                                }
                            }
                        } else {
                            Text("Agents use their normal approval flow.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider().padding(.vertical, 18)

                    setupSection(number: "3", title: "Phone control") {
                        Text(
                            "Open Codex Desktop, choose Set up Remote, and scan its QR code with the ChatGPT phone app. The Mac must stay awake, online, signed in, and running Codex Desktop."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button(manager.isOpeningCodexDesktop ? "Opening Codex…" : "Open this workspace in Codex") {
                                manager.openCodexDesktop()
                            }
                            .disabled(manager.isOpeningCodexDesktop)
                            Button("Set up Remote") { manager.openRemoteSetup() }
                            Link(
                                "Remote setup guide",
                                destination: URL(string: "https://learn.chatgpt.com/docs/remote-connections")!
                            )
                            Spacer()
                        }

                        Toggle(
                            "I opened Remote on my phone and confirmed this Mac is available",
                            isOn: Binding(
                                get: { manager.preferences.remoteSetupConfirmed },
                                set: { manager.setRemoteSetupConfirmed($0) }
                            )
                        )
                        .font(.system(size: 11.5))
                    }

                    Divider().padding(.vertical, 18)

                    setupSection(number: "4", title: "Setup health") {
                        HStack {
                            Text("Required tools and the desktop connection are checked from your login environment.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Check again") { manager.refreshHealth() }
                        }

                        if manager.isCheckingHealth {
                            ProgressView().controlSize(.small)
                        } else {
                            ForEach(manager.healthChecks) { check in
                                Label {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(check.label + (check.isRequired ? "" : " — optional"))
                                        Text(check.detail)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                } icon: {
                                    Image(
                                        systemName: check.isReady
                                            ? "checkmark.circle.fill" : (check.isRequired ? "exclamationmark.circle.fill" : "minus.circle")
                                    )
                                    .foregroundStyle(check.isReady ? Color.green : (check.isRequired ? Color.orange : Color.secondary))
                                }
                                .font(.system(size: 11, weight: .medium))
                            }
                        }

                        Divider()
                        HStack(spacing: 12) {
                            Text("History: \(ByteCountFormatter.string(fromByteCount: manager.transcriptDiskUsage, countStyle: .file))")
                            Text("Attachments: \(ByteCountFormatter.string(fromByteCount: manager.attachmentDiskUsage, countStyle: .file))")
                            Spacer()
                            Button("Reveal data") { manager.openRuntimeStorage() }
                            Menu("Clean up") {
                                Button("Delete copied attachments…") { cleanupRequest = .attachments }
                                Button("Delete transcripts from closed terminals…") { cleanupRequest = .transcripts }
                            }
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Text(manager.isSetupReady ? "Ready. Setup can be reopened later." : "Complete the highlighted checks to continue.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Start using the terminal") { manager.finishSetup() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!manager.isSetupReady)
            }
        }
        .padding(28)
        .frame(width: 660, height: 680)
        .onAppear { manager.refreshHealth() }
        .confirmationDialog(
            cleanupRequest?.title ?? "Clean up app data?",
            isPresented: Binding(
                get: { cleanupRequest != nil },
                set: { if !$0 { cleanupRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let cleanupRequest {
                Button(cleanupRequest.actionTitle, role: .destructive) {
                    switch cleanupRequest {
                    case .attachments: manager.clearCopiedAttachments()
                    case .transcripts: manager.clearInactiveTranscripts()
                    }
                    self.cleanupRequest = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(cleanupRequest?.message ?? "")
        }
    }

    private func setupSection<Content: View>(
        number: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
