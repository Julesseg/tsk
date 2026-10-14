import Foundation

public struct TaskRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var attributes: [String: String]

    public init(id: UUID, attributes: [String: String]) {
        self.id = id
        self.attributes = attributes
    }

    public var description: String { attributes["description"] ?? "Untitled task" }
    public var status: String { attributes["status"] ?? "unknown" }
    public var isRecurring: Bool { status == "recurring" || attributes["parent"] != nil || attributes["recur"] != nil }
}

public struct TaskDraft: Equatable, Sendable {
    public var description: String
    public var attributes: [String: String]

    public init(description: String = "", attributes: [String: String] = [:]) {
        self.description = description
        self.attributes = attributes
    }
}

public protocol TaskReplica: Sendable {
    func tasks() async throws -> [TaskRecord]
    func create(id: UUID, attributes: [String: String]) async throws -> TaskRecord
}

public enum TaskManagementError: Error, Equatable, LocalizedError, Sendable {
    case emptyDescription
    case unsupportedTaskKind
    case taskNotFound(UUID)
    case storage(String)

    public var errorDescription: String? {
        switch self {
        case .emptyDescription: "Enter a task description before saving."
        case .unsupportedTaskKind: "Recurring tasks require the recurrence editor. This capture flow creates ordinary tasks."
        case .taskNotFound: "This task is no longer available."
        case .storage(let message): "Local task storage failed: \(message)"
        }
    }
}

public actor TaskManager {
    let replica: any TaskReplica
    private let now: @Sendable () -> Date

    public init(replica: any TaskReplica, now: @escaping @Sendable () -> Date = { Date() }) {
        self.replica = replica
        self.now = now
    }

    public func tasks() async throws -> [TaskRecord] {
        try await replica.tasks().sorted {
            if $0.attributes["entry"] != $1.attributes["entry"] {
                return ($0.attributes["entry"] ?? "") > ($1.attributes["entry"] ?? "")
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public func task(id: UUID) async throws -> TaskRecord {
        guard let task = try await tasks().first(where: { $0.id == id }) else {
            throw TaskManagementError.taskNotFound(id)
        }
        return task
    }

    public func create(_ draft: TaskDraft) async throws -> TaskRecord {
        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { throw TaskManagementError.emptyDescription }
        guard draft.attributes["recur"] == nil, draft.attributes["parent"] == nil,
              draft.attributes["status"] == nil || draft.attributes["status"] == "pending" else {
            throw TaskManagementError.unsupportedTaskKind
        }
        var attributes = draft.attributes
        let timestamp = String(Int(now().timeIntervalSince1970))
        attributes["description"] = description
        attributes["status"] = "pending"
        attributes["entry"] = timestamp
        attributes["modified"] = timestamp
        return try await replica.create(id: UUID(), attributes: attributes)
    }
}
