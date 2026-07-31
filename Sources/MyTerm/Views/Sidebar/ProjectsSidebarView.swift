import SwiftUI

struct ProjectsSidebarView: View {
    @ObservedObject var manager: WorkspaceManager
    @State private var hoveredProject: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.trianglebadge.gearshape")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("WORKSPACE")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.78))
                    Text(manager.selectedWorkspaceURL.lastPathComponent)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundColor(.white.opacity(0.52))
                        .lineLimit(1)
                }

                Spacer()

                Button(action: {
                    manager.refreshProjects()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Refresh projects list")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .padding(.top, 38)

            Divider()
                .background(Color.white.opacity(0.08))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PROJECTS")
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .tracking(0.7)
                        .foregroundColor(.white.opacity(0.58))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    if manager.projectDirectories.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(manager.projectDiscoveryError == nil ? "No projects found" : "Couldn’t read projects")
                                .font(.system(size: 11, weight: .medium))
                            if let error = manager.projectDiscoveryError {
                                Text(error)
                                    .font(.system(size: 9))
                                    .lineLimit(3)
                            }
                        }
                        .foregroundColor(.white.opacity(0.48))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    } else {
                        ForEach(manager.projectDirectories, id: \.self) { dir in
                            ProjectRowView(dir: dir, manager: manager, hoveredProject: $hoveredProject)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(0.4)
                .background(Color.black.opacity(0.15))
        )
        .overlay(
            HStack {
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 1)
            }
        )
    }
}

struct ProjectRowView: View {
    let dir: URL
    @ObservedObject var manager: WorkspaceManager
    @Binding var hoveredProject: URL?

    var isHovered: Bool { hoveredProject == dir }

    var body: some View {
        Button(action: {
            manager.addSession(in: dir)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isHovered ? .blue : .white.opacity(0.68))
                    .frame(width: 18)

                Text(dir.lastPathComponent)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(.white.opacity(isHovered ? 0.96 : 0.82))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.85)

                Spacer()

                if isHovered {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.blue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                if hovering {
                    hoveredProject = dir
                } else if hoveredProject == dir {
                    hoveredProject = nil
                }
            }
        }
    }
}
