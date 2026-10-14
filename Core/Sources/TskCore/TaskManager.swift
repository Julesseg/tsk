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
    public var canEdit: Bool { !isRecurring && (status == "pending" || status == "completed") }
    public var canComplete: Bool { canEdit && status == "pending" }
    public var isRecurring: Bool { status == "recurring" || attributes["parent"] != nil || attributes["recur"] != nil || attributes["mask"] != nil || attributes["imask"] != nil }
}

public enum TaskQuery: String, CaseIterable, Sendable {
    case all, unfinished, completed, today, upcoming

    public func includes(_ task: TaskRecord, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Bool {
        switch self {
        case .all: true
        case .unfinished: task.status == "pending"
        case .completed: task.status == "completed"
        case .today: task.isInToday(at: now, calendar: calendar)
        case .upcoming: task.isInUpcoming(at: now, calendar: calendar)
        }
    }
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
    func update(id: UUID, changes: [String: String?]) async throws -> TaskRecord
}

public enum TaskManagementError: Error, Equatable, LocalizedError, Sendable {
    case invalidTag(String)
    case invalidPriority(String)
    case emptyDescription
    case unsupportedTaskKind
    case reservedAttribute(String)
    case taskNotFound(UUID)
    case storage(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTag(let tag): "The tag ‘\(tag)’ is invalid. Use a name without whitespace or a colon after its first character. Do not start with a digit or operator. Names made only of A–Z letters are reserved."
        case .invalidPriority(let priority): "Priority ‘\(priority)’ is unsupported. Choose H, M, L, or no priority."
        case .emptyDescription: "Enter a task description before saving."
        case .unsupportedTaskKind: "This action is unavailable for recurring templates, occurrences, or unsupported task states. Their attributes remain preserved."
        case .reservedAttribute(let name): "The \(name) attribute requires its dedicated task action."
        case .taskNotFound: "This task is no longer available."
        case .storage(let message): "Local task storage failed: \(message)"
        }
    }
}

public actor TaskManager {
    let replica: any TaskReplica
    let now: @Sendable () -> Date
    var synchronizationConfiguration: SyncConfiguration?
    var synchronizationState: SynchronizationState = .localOnly
    var synchronizationConfigurationGeneration = 0
    var synchronizationLocalGeneration = 0
    var synchronizationRequested = false
    var synchronizationTask: Task<Void, Never>?
    var synchronizationWaiters: [CheckedContinuation<[TaskRecord], any Error>] = []
    var synchronizationObservers: [UUID: AsyncStream<SynchronizationState>.Continuation] = [:]
    private let calendar: Calendar

    public init(replica: any TaskReplica, now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .autoupdatingCurrent) {
        self.replica = replica
        self.now = now
        self.calendar = calendar
    }

    public func tasks(query: TaskQuery = .all, project: TaskProjectSelection = .all) async throws -> [TaskRecord] {
        let instant = now()
        return try await replica.tasks().filter { query.includes($0, now: instant, calendar: calendar) && project.includes($0) }.sorted {
            if $0.attributes["entry"] != $1.attributes["entry"] {
                return ($0.attributes["entry"] ?? "") > ($1.attributes["entry"] ?? "")
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public func availability(id: UUID) async throws -> TaskAvailability {
        let record = try await task(id: id)
        return record.availability(at: now())
    }

    public func upcomingDays() async throws -> [UpcomingDay] {
        let records = try await replica.tasks()
        return UpcomingDay.groups(tasks: records, at: now(), calendar: calendar)
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
              draft.attributes["mask"] == nil, draft.attributes["imask"] == nil,
              draft.attributes["status"] == nil || draft.attributes["status"] == "pending" else {
            throw TaskManagementError.unsupportedTaskKind
        }
        var attributes = try TaskOrganization.normalizedAttributes(draft.attributes)
        let timestamp = String(Int(now().timeIntervalSince1970))
        attributes["description"] = description
        attributes["status"] = "pending"
        attributes["entry"] = timestamp
        attributes["modified"] = timestamp
        let saved = try await replica.create(id: UUID(), attributes: attributes)
        localChangeWasCommitted()
        return saved
    }

    public func update(id: UUID, changes: [String: String?]) async throws -> TaskRecord {
        let task = try await self.task(id: id)
        guard task.canEdit else { throw TaskManagementError.unsupportedTaskKind }
        let reserved = Set(["uuid", "id", "status", "entry", "modified", "end", "recur", "parent", "mask", "imask", "tags"])
        if let key = changes.keys.sorted().first(where: { reserved.contains($0) }) {
            throw TaskManagementError.reservedAttribute(key)
        }
        guard !changes.isEmpty else { return task }
        var patch = changes
        if changes.keys.contains("description") {
            let description = (changes["description"] ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !description.isEmpty else { throw TaskManagementError.emptyDescription }
            patch["description"] = description
        }
        patch = try TaskOrganization.normalizedChanges(patch, original: task.attributes)
        patch["modified"] = String(Int(now().timeIntervalSince1970))
        let saved = try await replica.update(id: id, changes: patch)
        localChangeWasCommitted()
        return saved
    }

    public func complete(id: UUID) async throws -> TaskRecord {
        let task = try await self.task(id: id)
        guard task.canEdit else { throw TaskManagementError.unsupportedTaskKind }
        if task.status == "completed" { return task }
        let timestamp = String(Int(now().timeIntervalSince1970))
        let saved = try await replica.update(id: id, changes: [
            "status": "completed", "end": task.attributes["end"] ?? timestamp,
            "modified": timestamp, "start": nil
        ])
        localChangeWasCommitted()
        return saved
    }

}
