import MyTermCore
import SwiftUI

struct DynamicGridView: View {
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        GeometryReader { geometry in
            if let maxID = manager.maximizedSessionID, let maxSession = manager.sessions.first(where: { $0.id == maxID }) {
                GridCell(session: maxSession, manager: manager)
                    .id(maxSession.id)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .padding(.top, 8)
            } else {
                let columnCount = TerminalGridLayout.columnCount(width: geometry.size.width, sessionCount: manager.sessions.count)
                let columns = Array(
                    repeating: GridItem(.flexible(minimum: 380), spacing: 12),
                    count: columnCount
                )
                let rows = Int(ceil(Double(manager.sessions.count) / Double(columnCount)))
                let paneHeight = TerminalGridLayout.paneHeight(containerHeight: geometry.size.height, rows: rows)

                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(manager.sessions) { session in
                            GridCell(session: session, manager: manager)
                                .id(session.id)
                                .frame(height: paneHeight)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .padding(.top, 8)
                }
            }
        }
    }

}
