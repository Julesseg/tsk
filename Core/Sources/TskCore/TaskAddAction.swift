import Foundation

public struct AddTaskInput: Equatable, Sendable {
    public var description: String
    public var project: String?
    public var tags: [String]
    public var priority: String?
    public var scheduled: Date?
    public var deadline: Date?
    public var waitingUntil: Date?

    public init(description: String, project: String? = nil, tags: [String] = [], priority: String? = nil, scheduled: Date? = nil, deadline: Date? = nil, waitingUntil: Date? = nil) {
        self.description = description
        self.project = project
        self.tags = tags
        self.priority = priority
        self.scheduled = scheduled
        self.deadline = deadline
        self.waitingUntil = waitingUntil
    }

    public func validatedDraft() throws -> TaskDraft {
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TaskManagementError.emptyDescription }
        var draft = TaskDraft(description: description)
        draft.project = project ?? ""
        draft.priority = priority ?? ""
        if let priority, !["", "H", "M", "L"].contains(priority) { throw TaskManagementError.invalidPriority(priority) }
        for tag in tags { try draft.addTag(tag) }
        for (key, date) in [("scheduled", scheduled), ("due", deadline), ("wait", waitingUntil)] {
            if let date {
                let seconds = date.timeIntervalSince1970
                guard seconds.isFinite, abs(seconds) <= 253402300799 else { throw TaskActionError.invalidInput("Invalid \(key) timestamp.") }
                draft.attributes[key] = String(Int(seconds))
            }
        }
        return draft
    }
}

public extension TaskManager {
    func addTask(_ input: AddTaskInput) async throws -> TaskRecord {
        try await create(input.validatedDraft())
    }
}

public enum TaskActionError: Error, LocalizedError, Equatable, Sendable {
    case invalidInput(String)
    case resultTooLarge
    case navigationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message), .navigationFailed(let message): message
        case .resultTooLarge: "The result exceeds the callback URL limit. It was not truncated."
        }
    }
}
