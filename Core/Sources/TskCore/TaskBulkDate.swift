import Foundation

public enum TaskDateField: String, Sendable, CaseIterable {
    case scheduled, deadline

    var attribute: String { self == .scheduled ? "scheduled" : "due" }
    var precisionAttribute: String { self == .scheduled ? TaskScheduledDate.attribute : TaskScheduledDate.deadlineAttribute }
}

public enum TaskDateChange: Equatable, Sendable {
    case set(Date)
    case day(Date)
    case exact(TaskScheduledDate)
    case remove

    public func resolvedDate(replacing raw: String?, calendar: Calendar = .autoupdatingCurrent) throws -> Date? {
        planningDate(try value(replacing: raw, calendar: calendar))
    }

    func value(replacing raw: String?, calendar: Calendar) throws -> String? {
        let date: Date
        switch self {
        case .remove: return nil
        case .set(let value): date = value
        case .exact(let intent):
            guard intent.date.timeIntervalSince1970.isFinite, abs(intent.date.timeIntervalSince1970) <= 253402300799 else {
                throw TaskReschedulingError.invalidDate
            }
            date = intent.hasTime ? intent.date : calendar.startOfDay(for: intent.date)
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

    func patch(for task: TaskRecord, field: TaskDateField, calendar: Calendar) throws -> TaskAttributePatch {
        let original = task.attributes[field.attribute]
        let raw = try value(replacing: original, calendar: calendar)
        let date = planningDate(raw)
        var draft = TaskDraft(attributes: task.attributes)
        switch self {
        case .exact(let explicit):
            let intent = date.map { TaskScheduledDate(date: $0, hasTime: explicit.hasTime) }
            draft.setDateIntent(intent, for: field)
        case .day:
            draft.attributes[field.attribute] = raw
            if task.attributes[field.precisionAttribute] != nil, let date,
               let originalIntent = task.dateIntent(for: field, calendar: calendar) {
                draft.setDateIntent(TaskScheduledDate(date: date, hasTime: originalIntent.hasTime), for: field)
            }
        case .set:
            if raw != original {
                draft.attributes[field.attribute] = raw
                draft.attributes[field.precisionAttribute] = nil
            }
        case .remove: draft.setDateIntent(nil, for: field)
        }
        return draft.attributes.changes(comparedTo: task.attributes)
    }
}

public struct TaskSelectionChanges: Equatable, Sendable {
    public var scheduled: TaskDateChange?
    public var deadline: TaskDateChange?
    public var project: String?
    public var priority: String?
    public var tag: TaskSelectionTagChange?
    public var complete: Bool

    public init(scheduled: TaskDateChange? = nil, deadline: TaskDateChange? = nil, complete: Bool = false) {
        self.scheduled = scheduled
        self.deadline = deadline
        self.complete = complete
    }

    public subscript(field: TaskDateField) -> TaskDateChange? {
        get { field == .scheduled ? scheduled : deadline }
        set { if field == .scheduled { scheduled = newValue } else { deadline = newValue } }
    }

    public func modifies(tasks: [TaskRecord], calendar: Calendar = .autoupdatingCurrent) throws -> Bool {
        guard !tasks.isEmpty else { return false }
        return try complete || tasks.contains { try !organizationPatch(for: $0).isEmpty } || TaskDateField.allCases.contains { try modifies($0, tasks: tasks, calendar: calendar) }
    }

    public func modifies(_ field: TaskDateField, tasks: [TaskRecord], calendar: Calendar = .autoupdatingCurrent) throws -> Bool {
        guard let change = self[field] else { return false }
        return try tasks.contains { try !change.patch(for: $0, field: field, calendar: calendar).isEmpty }
    }
}

extension TaskManager {
    public func changeDate(ids: [UUID], field: TaskDateField, change: TaskDateChange) async throws -> [TaskRecord] {
        var changes = TaskSelectionChanges()
        changes[field] = change
        return try await applySelection(ids: ids, changes: changes)
    }

    public func applySelection(ids: [UUID], changes: TaskSelectionChanges) async throws -> [TaskRecord] {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let ids = Set(ids)
        guard !ids.isEmpty else { return [] }
        let records = try await replica.tasks()
        let instant = now()
        let timestamp = String(Int(instant.timeIntervalSince1970))
        var updates: [TaskAtomicUpdate] = []
        var parents: [UUID: TaskRecord] = [:]
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let task = records.first(where: { $0.id == id }) else { throw TaskManagementError.taskNotFound(id) }
            guard task.canComplete else { throw TaskManagementError.unsupportedTaskKind }
            var patch = try changes.organizationPatch(for: task)
            for field in TaskDateField.allCases {
                if let change = changes[field] {
                    for (key, value) in try change.patch(for: task, field: field, calendar: calendar) {
                        patch.updateValue(value, forKey: key)
                    }
                }
            }
            try validateScheduledChange(patch, original: task.attributes, at: instant)
            if changes.complete {
                var placed = task
                for (key, value) in patch { placed.attributes[key] = value }
                for (key, value) in completionChanges(for: placed, at: instant) { patch.updateValue(value, forKey: key) }
            }
            if task.isOccurrence {
                let (parent, index) = try occurrencePosition(task, in: records)
                let byte = try occurrenceMutationMask(task, changes: patch, parent: parent, index: index, completing: changes.complete)
                guard !patch.isEmpty else { continue }
                var updated = parents[parent.id] ?? parent
                var mask = Array(updated.attributes["mask"]!.utf8)
                mask[index] = byte
                updated.attributes["mask"] = String(decoding: mask, as: UTF8.self)
                parents[parent.id] = updated
            }
            guard !patch.isEmpty else { continue }
            patch["modified"] = timestamp
            updates.append(TaskAtomicUpdate(id: id, expected: task.attributes, changes: patch))
        }
        for parent in parents.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let original = records.first { $0.id == parent.id }!
            if parent.attributes != original.attributes {
                updates.append(TaskAtomicUpdate(id: parent.id, expected: original.attributes,
                                                changes: ["mask": parent.attributes["mask"], "modified": timestamp]))
            }
        }
        guard !updates.isEmpty else { return records.filter { ids.contains($0.id) } }
        guard let atomic = replica as? any TaskAtomicSnapshotMutatingReplica else {
            throw TaskManagementError.storage("This storage adapter cannot save a selection atomically. No tasks were changed.")
        }
        let saved = try await atomic.updateAtomically(updates, expecting: records)
        await localChangeWasCommitted(tasks: saved)
        return records.filter { ids.contains($0.id) }.map { original in saved.first { $0.id == original.id } ?? original }
    }
}
