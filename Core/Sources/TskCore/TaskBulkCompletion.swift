import Foundation

extension TaskManager {
    public func complete(ids: [UUID]) async throws -> [TaskRecord] {
        try await applySelection(ids: ids, changes: TaskSelectionChanges(complete: true))
    }
}
