import Combine
import Foundation
import MyTermCore

private struct PlannerSnapshot: Codable {
    var shapes: [DrawingShape]
    var todoColumn: KanbanColumn
    var progressColumn: KanbanColumn
    var doneColumn: KanbanColumn
}

final class PlannerStore: ObservableObject {
    @Published var shapes: [DrawingShape] { didSet { scheduleSave() } }
    @Published var todoColumn: KanbanColumn { didSet { scheduleSave() } }
    @Published var progressColumn: KanbanColumn { didSet { scheduleSave() } }
    @Published var doneColumn: KanbanColumn { didSet { scheduleSave() } }
    @Published private(set) var persistenceError: String?

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.nicelookingterminal.planner-store", qos: .utility)
    private var pendingSave: DispatchWorkItem?

    init(fileURL: URL = MyTermPaths.applicationSupportDirectory.appendingPathComponent("planner.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
            let snapshot = try? JSONDecoder().decode(PlannerSnapshot.self, from: data)
        {
            shapes = snapshot.shapes
            todoColumn = snapshot.todoColumn
            progressColumn = snapshot.progressColumn
            doneColumn = snapshot.doneColumn
        } else {
            shapes = []
            todoColumn = KanbanColumn(name: "Backlog")
            progressColumn = KanbanColumn(name: "In Progress")
            doneColumn = KanbanColumn(name: "Done")
        }
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let currentSnapshot = snapshot()
        queue.sync {
            save(currentSnapshot)
        }
    }

    func dismissPersistenceError() {
        persistenceError = nil
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = snapshot()
        let work = DispatchWorkItem { [weak self] in
            self?.save(snapshot)
        }
        pendingSave = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func snapshot() -> PlannerSnapshot {
        PlannerSnapshot(
            shapes: shapes,
            todoColumn: todoColumn,
            progressColumn: progressColumn,
            doneColumn: doneColumn
        )
    }

    private func save(_ snapshot: PlannerSnapshot) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: fileURL.deletingLastPathComponent().path
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            DispatchQueue.main.async { [weak self] in self?.persistenceError = nil }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.persistenceError = "Planner changes could not be saved. \(error.localizedDescription)"
            }
        }
    }
}
