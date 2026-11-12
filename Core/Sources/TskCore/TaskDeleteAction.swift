import Foundation

public extension TaskManager {
    func delete(id: UUID) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let task = try await self.task(id: id)
        if task.status == "deleted" { return task }
        guard ["pending", "completed"].contains(task.status), task.isOccurrence || !task.isRecurring else {
            throw TaskManagementError.unsupportedTaskKind
        }
        let timestamp = String(Int(now().timeIntervalSince1970))
        let changes: TaskAttributePatch = ["status": "deleted", "end": task.attributes["end"] ?? timestamp, "modified": timestamp, "start": nil]
        if task.isOccurrence { return try await saveOccurrence(task, changes: changes, deleting: true) }
        return try await saveTaskMutation(task, changes: changes)
    }

    func openTask(id: UUID) async throws -> TaskRecord {
        let task = try await self.task(id: id)
        guard task.status != "deleted" else { throw TaskManagementError.taskNotFound(id) }
        return task
    }
}
