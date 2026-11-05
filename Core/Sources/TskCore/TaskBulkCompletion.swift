import Foundation

extension TaskManager {
    public func complete(ids: [UUID]) async throws -> [TaskRecord] {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let ids = Set(ids)
        guard !ids.isEmpty else { return [] }
        let records = try await replica.tasks()
        let timestamp = String(Int(now().timeIntervalSince1970))
        var updates: [TaskAtomicUpdate] = []
        var parents: [UUID: TaskRecord] = [:]
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let task = records.first(where: { $0.id == id }) else { throw TaskManagementError.taskNotFound(id) }
            guard task.canComplete else { throw TaskManagementError.unsupportedTaskKind }
            if task.isOccurrence {
                let (parent, index) = try occurrencePosition(task, in: records)
                guard [45, 87].contains(Array(parent.attributes["mask"]!.utf8)[index]) else {
                    throw TaskManagementError.storage("The occurrence state disagrees with its series mask. No tasks were changed.")
                }
                var changed = parents[parent.id] ?? parent
                var mask = Array(changed.attributes["mask"]!.utf8)
                mask[index] = 43
                changed.attributes["mask"] = String(decoding: mask, as: UTF8.self)
                parents[parent.id] = changed
            }
            updates.append(TaskAtomicUpdate(id: id, expected: task.attributes, changes: [
                "status": "completed", "end": task.attributes["end"] ?? timestamp, "modified": timestamp, "start": nil
            ]))
        }
        for parent in parents.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let original = records.first { $0.id == parent.id }!
            updates.append(TaskAtomicUpdate(id: parent.id, expected: original.attributes, changes: ["mask": parent.attributes["mask"], "modified": timestamp]))
        }
        guard let atomic = replica as? any TaskAtomicSnapshotMutatingReplica else {
            throw TaskManagementError.storage("This storage adapter cannot complete a selection atomically. No tasks were changed.")
        }
        let saved = try await atomic.updateAtomically(updates, expecting: records)
        await localChangeWasCommitted(tasks: saved)
        return saved.filter { ids.contains($0.id) }
    }
}
