import Foundation
import TskCore

struct CustomViewSelection: Equatable {
    let id: UUID?
    let name: String
    let expression: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name.matchesBytes(rhs.name) && lhs.expression.matchesBytes(rhs.expression)
    }
}

extension TaskStore {
    func loadSavedViews() async throws {
        savedViews = try await manager.savedViews()
        try loadWorkspaceViews()
    }

    func openView(_ view: SavedTaskView) {
        customView = CustomViewSelection(id: view.id, name: view.name, expression: view.expression)
    }
}

