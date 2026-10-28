import Foundation

public struct TaskRowDraft: Equatable, Sendable {
    public enum Plan: Sendable { case today, tomorrow, remove }
    public let original: TaskRecord
    public var taskDraft: TaskDraft
    public var tagInput = ""

    public init(task: TaskRecord) {
        original = task
        taskDraft = TaskDraft(description: task.description, attributes: task.attributes)
    }

    public mutating func plan(_ plan: Plan, now: Date, calendar: Calendar = .autoupdatingCurrent) {
        switch plan {
        case .today: taskDraft.plannedDate = calendar.startOfDay(for: now)
        case .tomorrow: taskDraft.plannedDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        case .remove: taskDraft.plannedDate = nil
        }
    }

    public mutating func choosePlannedDay(_ day: Date, calendar: Calendar = .autoupdatingCurrent) {
        taskDraft.plannedDate = calendar.startOfDay(for: day)
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
        for key in ["project", "priority", "scheduled", "due", "wait"] { edited[key] = taskDraft.attributes[key] }
        let tagKeys = Set(original.attributes.keyIdentities).union(organization.taskDraft.attributes.keyIdentities)
            .filter { $0.rawValue.utf8.starts(with: "tag_".utf8) }
        for key in tagKeys { edited[key.rawValue] = organization.taskDraft.attributes[key.rawValue] }
        return edited.changes(comparedTo: original.attributes)
    }
}
