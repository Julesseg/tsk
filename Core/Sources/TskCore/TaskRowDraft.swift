import Foundation

public enum TaskCaptureContext: Equatable, Sendable {
    case day(Date), project(String), inbox, external

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.day(let left), .day(let right)): left == right
        case (.project(let left), .project(let right)): left.matchesBytes(right)
        case (.inbox, .inbox), (.external, .external): true
        default: false
        }
    }
}

public struct TaskRowDraft: Equatable, Sendable {
    private static let editableAttributes = ["project", "priority", "scheduled", "due", TaskScheduledDate.attribute]
    public enum Plan: Sendable { case today, tomorrow, remove }
    public let original: TaskRecord
    public var taskDraft: TaskDraft
    public var tagInput = ""
    public var noteInput = ""

    public init(task: TaskRecord) {
        original = task
        taskDraft = TaskDraft(description: task.description, attributes: task.attributes)
    }

    public init(capturing query: TaskQuery, project: TaskProjectSelection = .all, now: Date, calendar: Calendar = .autoupdatingCurrent) {
        let context: TaskCaptureContext
        if query == .today { context = .day(now) }
        else if let name = project.projectName { context = .project(name) }
        else { context = .inbox }
        self.init(capturing: context, calendar: calendar)
        if let name = project.projectName { taskDraft.project = name }
    }

    public init(capturing context: TaskCaptureContext, calendar: Calendar = .autoupdatingCurrent) {
        var draft = TaskDraft()
        switch context {
        case .day(let day): draft.schedule(on: day, calendar: calendar)
        case .project(let name): draft.project = name
        case .inbox, .external: break
        }
        original = TaskRecord(id: UUID(), attributes: ["description": "", "status": "pending"])
        taskDraft = draft
    }

    public func creationDraft(at date: Date) throws -> TaskDraft {
        var draft = self
        try draft.addTagInput()
        _ = try draft.changes()
        if !noteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let task = TaskRecord(id: original.id, attributes: draft.taskDraft.attributes)
            draft.taskDraft.attributes[try task.nextAnnotationReference(at: date)] = noteInput
        }
        return draft.taskDraft
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

public extension TaskManager {
    func updateRow(_ draft: TaskRowDraft) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let changes = try draft.changes()
        let current = try await task(id: draft.original.id)
        var notes: TaskAttributePatch = [:]
        for annotation in draft.original.annotations {
            let reference = annotation.reference.rawValue
            let text = draft.taskDraft.attributes[reference] ?? ""
            guard !text.matchesBytes(annotation.text) else { continue }
            guard current.attributes[reference] != nil else { throw TaskManagementError.annotationNotFound(reference) }
            notes.updateValue(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text, forKey: reference)
        }
        if !draft.noteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes[try current.nextAnnotationReference(at: now())] = draft.noteInput
        }
        return try await updateTask(id: current.id, changes: changes, annotationChanges: notes)
    }
}
