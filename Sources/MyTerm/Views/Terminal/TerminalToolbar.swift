import MyTermCore
import SwiftUI

struct ModeButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 12.5, weight: .bold))
            .foregroundColor(isSelected ? .white : .gray)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct TopNavigationBar: View {
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        HStack {
            // Sidebar Toggle & Segmented Switcher
            HStack(spacing: 12) {
                if manager.mode == .terminals {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            manager.showSidebar.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(manager.showSidebar ? .blue : .white.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(manager.showSidebar ? 0.12 : 0.05))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Projects Sidebar")
                }

                HStack(spacing: 4) {
                    ModeButton(title: "Terminals", icon: "terminal", isSelected: manager.mode == .terminals) {
                        withAnimation(.easeInOut(duration: 0.2)) { manager.mode = .terminals }
                    }
                    ModeButton(title: "Planner", icon: "square.and.pencil", isSelected: manager.mode == .planner) {
                        withAnimation(.easeInOut(duration: 0.2)) { manager.mode = .planner }
                    }
                }
                .padding(4)
                .background(Color.black.opacity(0.3))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.04), lineWidth: 1))
            }

            Spacer()

            if manager.mode == .terminals {
                HStack(spacing: 6) {
                    Text("\(manager.sessions.count) terminal\(manager.sessions.count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button(action: { manager.openCodexDesktop() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.hexagongrid.fill")
                            Text("Open Codex")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.72))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.isOpeningCodexDesktop)
                    .help("Open the selected workspace in Codex Desktop for phone Remote")

                    Button(action: { manager.addSession() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("New Tab")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    AgentPresetMenu(manager: manager)

                    Button(action: { manager.runSetupAgain() }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Setup and access")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.leading, (manager.mode == .terminals && manager.showSidebar) ? 14 : 70)
    }
}

struct AgentPresetMenu: View {
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        Menu {
            Button(action: { manager.openCodexDesktop() }) {
                Label("Codex Desktop — phone-ready", systemImage: "macwindow")
            }

            Divider()

            ForEach(AgentPreset.allCases, id: \.self) { preset in
                Button(action: { manager.runPreset(preset) }) {
                    HStack {
                        Image(systemName: preset.symbolName)
                        Text(preset.title)
                        Spacer()
                        Text("⌘\(preset.shortcut.uppercased())")
                            .foregroundColor(.gray)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                AgentLogoBadge(text: "G", color: .blue)
                AgentLogoBadge(text: "AI", color: .green)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Open agent tab")
    }
}

struct AgentLogoBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: text.count > 1 ? 8 : 10, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 18, height: 18)
            .background(color.opacity(0.8))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}
