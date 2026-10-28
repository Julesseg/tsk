import Foundation

public struct TaskRowDraft: Equatable, Sendable {
    public enum Plan: Sendable { case today, tomorrow, remove }
    public let original: TaskRecord
    public var taskDraft: TaskDraft

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

    public func changes() throws -> TaskAttributePatch {
        guard original.canEdit else { throw TaskManagementError.unsupportedTaskKind }
        let title = taskDraft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TaskManagementError.emptyDescription }
        var edited = original.attributes
        if !taskDraft.description.matchesBytes(original.description) { edited["description"] = title }
        for key in ["project", "priority", "scheduled", "due", "wait"] { edited[key] = taskDraft.attributes[key] }
        return edited.changes(comparedTo: original.attributes)
    }
}
