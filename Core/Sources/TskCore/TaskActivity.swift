import Foundation

public extension TaskRecord {
    var isActive: Bool { attributes["start"] != nil }
    var canChangeActivity: Bool { status == "pending" && canEdit }
}

public extension TaskManager {
    func start(id: UUID) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let task = try await task(id: id)
        guard task.canChangeActivity else { throw TaskManagementError.unsupportedTaskKind }
        guard !task.isActive else { return task }
        let timestamp = String(Int(now().timeIntervalSince1970))
        return try await saveTaskMutation(task, changes: ["start": timestamp, "modified": timestamp])
    }

    func stop(id: UUID) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let task = try await task(id: id)
        guard task.canChangeActivity else { throw TaskManagementError.unsupportedTaskKind }
        guard task.isActive else { return task }
        return try await saveTaskMutation(task, changes: ["start": nil, "modified": String(Int(now().timeIntervalSince1970))])
    }
}
