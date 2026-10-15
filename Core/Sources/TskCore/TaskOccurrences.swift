import Foundation

public struct TaskAtomicUpdate: Codable, Sendable {
    public let id: UUID
    public let expected: TaskAttributes
    public let changes: TaskAttributePatch

    public init(id: UUID, expected: TaskAttributes, changes: TaskAttributePatch) {
        self.id = id
        self.expected = expected
        self.changes = changes
    }
}

public protocol TaskAtomicMutatingReplica: TaskReplica {
    func updateAtomically(_ updates: [TaskAtomicUpdate]) async throws -> [TaskRecord]
}

extension TaskManager {
    func saveTaskMutation(_ task: TaskRecord, changes: TaskAttributePatch) async throws -> TaskRecord {
        if task.isOccurrence { return try await saveOccurrence(task, changes: changes) }
        let saved = try await replica.update(id: task.id, changes: changes)
        await localChangeWasCommitted()
        return saved
    }

    func saveOccurrence(_ occurrence: TaskRecord, changes: TaskAttributePatch, completing: Bool = false) async throws -> TaskRecord {
        let records = try await replica.tasks()
        guard let rawParent = occurrence.attributes["parent"], let parentID = UUID(uuidString: rawParent), parentID != occurrence.id,
              let parent = records.first(where: { $0.id == parentID }),
              ["recurring", "deleted"].contains(parent.status), parent.attributes["parent"] == nil,
              let rawIndex = occurrence.attributes["imask"], !rawIndex.isEmpty,
              rawIndex.utf8.allSatisfy({ (48...57).contains($0) }), let index = Int(rawIndex),
              let rawMask = parent.attributes["mask"], rawMask.utf8.allSatisfy({ [45, 87, 43, 88].contains($0) }),
              index < rawMask.utf8.count else { throw TaskManagementError.storage("The occurrence’s parent, index, or series mask is inconsistent. No tasks were changed.") }
        let siblings = records.filter { UUID(uuidString: $0.attributes["parent"] ?? "") == parentID && Int($0.attributes["imask"] ?? "") == index }
        guard siblings.count == 1 else { throw TaskManagementError.storage("More than one occurrence uses this series position. No tasks were changed.") }
        var mask = Array(rawMask.utf8)
        if occurrence.status == "completed", completing, mask[index] == 43 { return occurrence }
        guard occurrence.status == "pending", [45, 87].contains(mask[index]) else { throw TaskManagementError.storage("The occurrence state disagrees with its series mask. No tasks were changed.") }
        guard let atomic = replica as? any TaskAtomicMutatingReplica else { throw TaskManagementError.storage("This storage adapter cannot save recurrence bookkeeping atomically.") }
        if completing { mask[index] = 43 }
        else {
            if changes.keys.contains("due"), (changes["due"] ?? nil)?.isEmpty != false { throw TaskManagementError.storage("A generated occurrence must retain its due date. No tasks were changed.") }
            let value = changes.keys.contains("wait") ? changes["wait"] ?? nil : occurrence.attributes["wait"]
            if let value, let seconds = TimeInterval(value), seconds.isFinite { mask[index] = seconds > now().timeIntervalSince1970 ? 87 : 45 }
            else if value == nil { mask[index] = 45 }
            else { throw TaskManagementError.storage("The occurrence wait date is invalid. No tasks were changed.") }
        }
        let parentChanges: TaskAttributePatch = String(decoding: mask, as: UTF8.self).matchesBytes(rawMask) ? [:] : ["mask": String(decoding: mask, as: UTF8.self), "modified": String(Int(now().timeIntervalSince1970))]
        let saved = try await atomic.updateAtomically([
            TaskAtomicUpdate(id: occurrence.id, expected: occurrence.attributes, changes: changes),
            TaskAtomicUpdate(id: parent.id, expected: parent.attributes, changes: parentChanges)
        ])
        guard let result = saved.first(where: { $0.id == occurrence.id }) else { throw TaskManagementError.storage("The atomic save returned no occurrence.") }
        await localChangeWasCommitted()
        return result
    }
}
