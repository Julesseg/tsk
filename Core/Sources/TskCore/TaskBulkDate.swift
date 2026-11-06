import Foundation

public enum TaskDateField: String, Sendable, CaseIterable {
    case scheduled, deadline

    var attribute: String { self == .scheduled ? "scheduled" : "due" }
}

public enum TaskDateChange: Equatable, Sendable {
    case set(Date)
    case day(Date)
    case remove

    func value(replacing raw: String?, calendar: Calendar) throws -> String? {
        let date: Date
        switch self {
        case .remove: return nil
        case .set(let value): date = value
        case .day(let day):
            guard day.timeIntervalSince1970.isFinite, abs(day.timeIntervalSince1970) <= 253402300799 else {
                throw TaskManagementError.storage("Choose a valid calendar day. No tasks were changed.")
            }
            guard let resolved = taskDate(on: day, keepingTimeFrom: planningDate(raw), calendar: calendar) else {
                throw TaskManagementError.storage("Choose a valid calendar day. No tasks were changed.")
            }
            date = resolved
        }
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, abs(seconds) <= 253402300799 else {
            throw TaskManagementError.storage("Choose a valid date. No tasks were changed.")
        }
        return String(Int(seconds))
    }
}

extension TaskManager {
    public func changeDate(ids: [UUID], field: TaskDateField, change: TaskDateChange) async throws -> [TaskRecord] {
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
            let value = try change.value(replacing: task.attributes[field.attribute], calendar: calendar)
            let changes: TaskAttributePatch = [field.attribute: value, "modified": timestamp]
            if task.isOccurrence {
                let (parent, index) = try occurrencePosition(task, in: records)
                let byte = try occurrenceMutationMask(task, changes: changes, parent: parent, index: index)
                var updated = parents[parent.id] ?? parent
                var mask = Array(updated.attributes["mask"]!.utf8)
                mask[index] = byte
                updated.attributes["mask"] = String(decoding: mask, as: UTF8.self)
                parents[parent.id] = updated
            }
            updates.append(TaskAtomicUpdate(id: id, expected: task.attributes, changes: changes))
        }
        for parent in parents.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let original = records.first { $0.id == parent.id }!
            if parent.attributes != original.attributes {
                updates.append(TaskAtomicUpdate(id: parent.id, expected: original.attributes,
                                                changes: ["mask": parent.attributes["mask"], "modified": timestamp]))
            }
        }
        guard let atomic = replica as? any TaskAtomicSnapshotMutatingReplica else {
            throw TaskManagementError.storage("This storage adapter cannot change selection dates atomically. No tasks were changed.")
        }
        let saved = try await atomic.updateAtomically(updates, expecting: records)
        await localChangeWasCommitted(tasks: saved)
        return saved.filter { ids.contains($0.id) }
    }
}
