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
        await localChangeWasCommitted(tasks: [saved])
        return saved
    }

    func saveOccurrence(_ occurrence: TaskRecord, changes: TaskAttributePatch, completing: Bool = false, deleting: Bool = false) async throws -> TaskRecord {
        let records = try await replica.tasks()
        let (parent, index) = try occurrencePosition(occurrence, in: records)
        let rawMask = parent.attributes["mask"]!
        var mask = Array(rawMask.utf8)
        if occurrence.status == "completed", completing, mask[index] == 43 { return occurrence }
        guard let atomic = replica as? any TaskAtomicMutatingReplica else { throw TaskManagementError.storage("This storage adapter cannot save recurrence bookkeeping atomically.") }
        mask[index] = try occurrenceMutationMask(occurrence, changes: changes, parent: parent, index: index, completing: completing, deleting: deleting)
        let parentChanges: TaskAttributePatch = String(decoding: mask, as: UTF8.self).matchesBytes(rawMask) ? [:] : ["mask": String(decoding: mask, as: UTF8.self), "modified": String(Int(now().timeIntervalSince1970))]
        let saved = try await atomic.updateAtomically([
            TaskAtomicUpdate(id: occurrence.id, expected: occurrence.attributes, changes: changes),
            TaskAtomicUpdate(id: parent.id, expected: parent.attributes, changes: parentChanges)
        ])
        guard let result = saved.first(where: { $0.id == occurrence.id }) else { throw TaskManagementError.storage("The atomic save returned no occurrence.") }
        await localChangeWasCommitted(tasks: saved)
        return result
    }

    func occurrenceMutationMask(_ occurrence: TaskRecord, changes: TaskAttributePatch, parent: TaskRecord, index: Int, completing: Bool = false, deleting: Bool = false) throws -> UInt8 {
        let mask = Array(parent.attributes["mask"]!.utf8)[index]
        let validPending = occurrence.status == "pending" && [45, 87].contains(mask)
        let validCompletedDeletion = deleting && occurrence.status == "completed" && mask == 43
        guard validPending || validCompletedDeletion else {
            throw TaskManagementError.storage("The occurrence state disagrees with its series mask. No tasks were changed.")
        }
        if deleting { return 88 }
        if changes.keys.contains("due"), (changes["due"] ?? nil)?.isEmpty != false {
            throw TaskManagementError.storage("A generated occurrence must retain its due date. Change its deadline instead, or deselect it before removing deadlines. No tasks were changed.")
        }
        if completing { return 43 }
        let value = changes.keys.contains("wait") ? changes["wait"] ?? nil : occurrence.attributes["wait"]
        if let value, let seconds = TimeInterval(value), seconds.isFinite { return seconds > now().timeIntervalSince1970 ? 87 : 45 }
        if value == nil { return 45 }
        throw TaskManagementError.storage("The occurrence wait date is invalid. No tasks were changed.")
    }

    func occurrencePosition(_ occurrence: TaskRecord, in records: [TaskRecord]) throws -> (TaskRecord, Int) {
        guard let rawParent = occurrence.attributes["parent"], let parentID = UUID(uuidString: rawParent), parentID != occurrence.id,
              let parent = records.first(where: { $0.id == parentID }),
              ["recurring", "deleted"].contains(parent.status), parent.attributes["parent"] == nil,
              let index = occurrence.occurrenceIndex,
              let rawMask = parent.attributes["mask"], rawMask.utf8.allSatisfy({ [45, 87, 43, 88].contains($0) }),
              index < rawMask.utf8.count else {
            throw TaskManagementError.storage("The occurrence’s parent, index, or series mask is inconsistent. No tasks were changed.")
        }
        guard records.filter({ UUID(uuidString: $0.attributes["parent"] ?? "") == parentID && $0.occurrenceIndex == index }).count == 1 else {
            throw TaskManagementError.storage("More than one occurrence uses this series position. No tasks were changed.")
        }
        return (parent, index)
    }
}
