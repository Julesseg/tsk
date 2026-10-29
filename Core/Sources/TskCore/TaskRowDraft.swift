import Foundation

public struct TaskRowDraft: Equatable, Sendable {
    private static let editableAttributes = ["project", "priority", "scheduled", "due", "wait"]
    public enum Plan: Sendable { case today, tomorrow, remove }
    public private(set) var original: TaskRecord
    public var taskDraft: TaskDraft
    public var tagInput = ""

    public init(task: TaskRecord) {
        original = task
        taskDraft = TaskDraft(description: task.description, attributes: task.attributes)
    }

    public mutating func rebase(on task: TaskRecord) {
        guard task.id == original.id else { return }
        let title = taskDraft.description
        let titleChanged = !title.matchesBytes(original.description)
        let edits = taskDraft.attributes.changes(comparedTo: original.attributes)
        original = task
        taskDraft = TaskDraft(description: task.description, attributes: task.attributes)
        if titleChanged { taskDraft.description = title }
        let editedKeys = Self.editableAttributes + edits.keys.filter { $0.utf8.starts(with: "tag_".utf8) }
        for key in editedKeys {
            if let value = edits[key] { taskDraft.attributes[key] = value }
        }
    }

    public mutating func plan(_ plan: Plan, now: Date, calendar: Calendar = .autoupdatingCurrent) {
        switch plan {
        case .today: taskDraft.schedule(on: now, calendar: calendar)
        case .tomorrow:
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) { taskDraft.schedule(on: tomorrow, calendar: calendar) }
        case .remove: taskDraft.plannedDate = nil
        }
    }

    public mutating func chooseScheduledDate(_ date: Date) {
        taskDraft.plannedDate = date
    }

    public mutating func addTagInput() throws {
        guard !tagInput.isEmpty else { return }
        try taskDraft.addTag(tagInput)
        tagInput = ""
    }

    public func changes() throws -> TaskAttributePatch {
        guard original.canEdit else { throw TaskManagementError.unsupportedTaskKind }
        let title = taskDraft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TaskManagementError.emptyDescription }
        var organization = self
        try organization.addTagInput()
        var edited = original.attributes
        if !taskDraft.description.matchesBytes(original.description) { edited["description"] = title }
        for key in Self.editableAttributes { edited[key] = taskDraft.attributes[key] }
        let tagKeys = Set(original.attributes.keyIdentities).union(organization.taskDraft.attributes.keyIdentities)
            .filter { $0.rawValue.utf8.starts(with: "tag_".utf8) }
        for key in tagKeys { edited[key.rawValue] = organization.taskDraft.attributes[key.rawValue] }
        return edited.changes(comparedTo: original.attributes)
    }
}
