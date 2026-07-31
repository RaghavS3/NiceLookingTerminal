import Foundation
import SwiftUI

enum CardPriority: String, Codable, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .gray
        }
    }
}

struct KanbanCard: Identifiable, Codable {
    var id = UUID()
    var title: String = "New Task"
    var description: String = ""
    var priority: CardPriority = .medium
    var isDone = false
    var imageData: Data? = nil
}

struct KanbanColumn: Identifiable, Codable {
    var id = UUID()
    var name: String
    var cards: [KanbanCard] = []
}
