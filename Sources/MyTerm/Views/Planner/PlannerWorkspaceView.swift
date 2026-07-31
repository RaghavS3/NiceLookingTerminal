import SwiftUI

struct PlannerWorkspaceView: View {
    @ObservedObject var store: PlannerStore
    @State private var subMode: PlannerSubMode = .whiteboard

    enum PlannerSubMode {
        case whiteboard
        case kanban
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) { subMode = .whiteboard }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.and.outline")
                        Text("Whiteboard")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(subMode == .whiteboard ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(subMode == .whiteboard ? Color.white.opacity(0.08) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) { subMode = .kanban }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.3x2.fill")
                        Text("Kanban Board")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(subMode == .kanban ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(subMode == .kanban ? Color.white.opacity(0.08) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(4)
            .background(Color.black.opacity(0.25))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.04), lineWidth: 1))
            .padding(.top, 10)

            ZStack {
                if subMode == .whiteboard {
                    WhiteboardView(shapes: $store.shapes)
                        .transition(.opacity)
                } else {
                    KanbanView(store: store)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert(
            "Planner save failed",
            isPresented: Binding(
                get: { store.persistenceError != nil },
                set: { if !$0 { store.dismissPersistenceError() } }
            )
        ) {
            Button("OK", role: .cancel) { store.dismissPersistenceError() }
        } message: {
            Text(store.persistenceError ?? "Unknown error")
        }
    }
}
