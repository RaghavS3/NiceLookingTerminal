import Foundation
import XCTest

@testable import MyTermApp

@MainActor
final class PlannerStoreTests: XCTestCase {
    func testPlannerStatePersistsAcrossStoreInstances() throws {
        let directories = try TemporaryTestDirectories()
        let fileURL = directories.applicationSupport.appendingPathComponent("planner.json")
        let store = PlannerStore(fileURL: fileURL)
        store.shapes = [
            DrawingShape(tool: .pen, points: [CGPoint(x: 1, y: 2), CGPoint(x: 4, y: 8)], text: "saved")
        ]
        store.todoColumn.cards = [KanbanCard(title: "Persist me", description: "Stored", priority: .high)]

        store.saveNow()

        let restored = PlannerStore(fileURL: fileURL)
        XCTAssertEqual(restored.shapes.count, 1)
        XCTAssertEqual(restored.shapes[0].points, [CGPoint(x: 1, y: 2), CGPoint(x: 4, y: 8)])
        XCTAssertEqual(restored.todoColumn.cards.map(\.title), ["Persist me"])
        XCTAssertEqual(restored.todoColumn.cards.first?.description, "Stored")
    }
}
