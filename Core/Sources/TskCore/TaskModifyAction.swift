import Foundation

public enum TaskTagOperation: String, CaseIterable, Sendable {
    case add, remove, replace, clear
}

public struct ModifyTaskInput: Equatable, Sendable {
    public var description: String?
    public var project: String?
    public var tags: [String]?
    public var tagOperation: TaskTagOperation
    public var priority: String?
    public var scheduled: Date?
    public var deadline: Date?
    public var waitingUntil: Date?
    public var clearProject: Bool
    public var clearPriority: Bool
    public var clearScheduled: Bool
    public var clearDeadline: Bool
    public var clearWaitingUntil: Bool

    public init(description: String? = nil, project: String? = nil, tags: [String]? = nil, tagOperation: TaskTagOperation = .add, priority: String? = nil, scheduled: Date? = nil, deadline: Date? = nil, waitingUntil: Date? = nil, clearProject: Bool = false, clearPriority: Bool = false, clearScheduled: Bool = false, clearDeadline: Bool = false, clearWaitingUntil: Bool = false) {
        self.description = description
        self.project = project
        self.tags = tags
        self.tagOperation = tagOperation
        self.priority = priority
        self.scheduled = scheduled
        self.deadline = deadline
        self.waitingUntil = waitingUntil
        self.clearProject = clearProject
        self.clearPriority = clearPriority
        self.clearScheduled = clearScheduled
        self.clearDeadline = clearDeadline
        self.clearWaitingUntil = clearWaitingUntil
    }

    public func validatedChanges(for task: TaskRecord) throws -> TaskAttributePatch {
        var changes: TaskAttributePatch = [:]
        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            changes["description"] = description
        }
        for (key, value, clear) in [("project", project, clearProject), ("priority", priority, clearPriority)] {
            let value = value?.isEmpty == false ? value : nil
            guard value == nil || !clear else { throw TaskActionError.invalidInput("Choose either a new \(key) or Clear, not both.") }
            if clear { changes.updateValue(nil, forKey: key) }
            else if let value { changes[key] = value }
        }
        for (key, date, clear) in [("scheduled", scheduled, clearScheduled), ("due", deadline, clearDeadline), ("wait", waitingUntil, clearWaitingUntil)] {
            guard date == nil || !clear else { throw TaskActionError.invalidInput("Choose either a new \(key) date or Clear, not both.") }
            if clear { changes.updateValue(nil, forKey: key) }
            else if let date {
                let seconds = date.timeIntervalSince1970
                guard seconds.isFinite, abs(seconds) <= 253402300799 else { throw TaskActionError.invalidInput("Invalid \(key) timestamp.") }
                changes[key] = String(Int(seconds))
            }
        }
        let tags = tags ?? []
        guard tagOperation != .clear || tags.isEmpty else { throw TaskActionError.invalidInput("Clear tags cannot also supply tags.") }
        for tag in tags { try TaskOrganization.validateTag(tag) }
        if tagOperation == .clear || (tagOperation == .replace && !tags.isEmpty) {
            for tag in task.tags { changes.updateValue(nil, forKey: "tag_" + tag) }
        }
        for tag in tags {
            changes.updateValue(tagOperation == .remove ? nil : "", forKey: "tag_" + tag)
        }
        _ = try TaskOrganization.normalizedChanges(changes, original: task.attributes)
        return changes
    }
}

public extension TaskManager {
    func modifyTask(id: UUID, input: ModifyTaskInput) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let task = try await task(id: id)
        guard task.status != "deleted" else { throw TaskActionError.invalidInput("This task was deleted and cannot be modified.") }
        return try await updateTask(id: id, changes: input.validatedChanges(for: task))
    }
}
