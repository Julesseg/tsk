import Foundation

public struct TaskRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var attributes: TaskAttributes

    public init(id: UUID, attributes: TaskAttributes) {
        self.id = id
        self.attributes = attributes
    }

    public var description: String { attributes["description"] ?? "Untitled task" }
    public var status: String { attributes["status"] ?? "unknown" }
    public var isOccurrence: Bool { attributes["parent"] != nil }
    public var canEdit: Bool { (isOccurrence && UUID(uuidString: attributes["parent"] ?? "") != nil && occurrenceIndex != nil && status == "pending") || (!isRecurring && (status == "pending" || status == "completed")) }
    public var canComplete: Bool { canEdit && status == "pending" }
    public var canReopen: Bool {
        status == "completed" && (isOccurrence ? UUID(uuidString: attributes["parent"] ?? "") != nil && occurrenceIndex != nil : !isRecurring)
    }
    public var isRecurring: Bool { status == "recurring" || attributes["parent"] != nil || attributes["recur"] != nil || attributes["mask"] != nil || attributes["imask"] != nil || attributes["rtype"] != nil || attributes["template"] != nil || attributes["last"] != nil }
}

public enum TaskQuery: String, CaseIterable, Sendable {
    case all, unfinished, completed, today, upcoming, inbox

    public func includes(_ task: TaskRecord, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Bool {
        switch self {
        case .all: true
        case .unfinished: task.status == "pending"
        case .inbox: task.status == "pending" && task.plannedDate == nil && task.project.isEmpty
        case .completed: task.status == "completed"
        case .today: task.isInToday(at: now, calendar: calendar)
        case .upcoming: task.isInUpcoming(at: now, calendar: calendar)
        }
    }
}

public struct TaskDraft: Equatable, Sendable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.description.matchesBytes(rhs.description) && lhs.attributes == rhs.attributes
    }

    public var description: String
    public var attributes: TaskAttributes

    public init(description: String = "", attributes: TaskAttributes = [:]) {
        self.description = description
        self.attributes = attributes
    }
}

public protocol TaskReplica: Sendable {
    func tasks() async throws -> [TaskRecord]
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord
}

public enum TaskManagementError: Error, Equatable, LocalizedError, Sendable {
    case invalidTag(String)
    case invalidPriority(String)
    case emptyAnnotation
    case invalidAnnotationTimestamp
    case annotationNotFound(String)
    case emptyDescription
    case unsupportedTaskKind
    case reservedAttribute(String)
    case taskNotFound(UUID)
    case taskDeleted(UUID)
    case storage(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTag(let tag): "The tag ‘\(tag)’ is invalid. Use a name without whitespace or a colon after its first character. Do not start with a digit or operator. Names made only of A–Z letters are reserved."
        case .invalidPriority(let priority): "Priority ‘\(priority)’ is unsupported. Choose H, M, L, or no priority."
        case .emptyAnnotation: "Enter annotation text before saving."
        case .invalidAnnotationTimestamp: "A valid timestamp could not be assigned to this annotation."
        case .annotationNotFound: "This annotation is no longer available. Reopen the task and try again."
        case .emptyDescription: "Enter a task description before saving."
        case .unsupportedTaskKind: "This action is unavailable for recurring templates or this saved task state. Its attributes remain preserved."
        case .reservedAttribute(let name): "The \(name) attribute requires its dedicated task action."
        case .taskNotFound: "This task is no longer available."
        case .taskDeleted: "This task has been deleted. No tasks were changed."
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
    var activeMutationScope: TaskMutationScope?
    let postCommitEffects: any TaskPostCommitEffect
    var mutationInProgress = false
    var mutationWaiters: [CheckedContinuation<Void, Never>] = []
    let changeTracking: any TaskChangeTracking
    var changePublicationError: String?
    let calendar: Calendar

    public init(replica: any TaskReplica, now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .autoupdatingCurrent, changeTracking: any TaskChangeTracking = TaskChangeLedger(), postCommitEffects: any TaskPostCommitEffect = TaskPostCommitEffects()) {
        self.replica = replica
        self.postCommitEffects = postCommitEffects
        self.changeTracking = changeTracking
        self.now = now
        self.calendar = calendar
    }

    public func tasks(query: TaskQuery = .all, project: TaskProjectSelection = .all) async throws -> [TaskRecord] {
        let instant = now()
        let records = try await replica.tasks().filter { query.includes($0, now: instant, calendar: calendar) && project.includes($0) }
        return sortedTasks(records, query: query, project: project, at: instant)
    }

    func sortedTasks(_ records: [TaskRecord], query: TaskQuery, project: TaskProjectSelection, at instant: Date) -> [TaskRecord] {
        let day = calendar.startOfDay(for: instant)
        return records.sorted {
            if query == .today { return TaskPlannerOrder.precedes($0, $1, on: day, calendar: calendar) }
            if case .project(let name) = project, let result = TaskManualOrder.precedes($0, $1, attribute: TaskManualOrder.projectAttribute, group: name) { return result }
            return TaskPlannerOrder.entryPrecedes($0, $1)
        }
    }

    public func dayPage(on day: Date) async throws -> [TaskRecord] {
        let records = try await tasks()
        return dayPage(on: day, in: records)
    }

    public func dayPage(on day: Date, in records: [TaskRecord]) -> [TaskRecord] {
        let instant = now()
        let dayStart = calendar.startOfDay(for: day)
        return records.filter { $0.isOnDay(dayStart, at: instant, calendar: calendar) }
            .sorted { TaskPlannerOrder.precedes($0, $1, on: dayStart, calendar: calendar) }
    }

    public func dayPageSnapshot(on day: Date) async throws -> TaskViewSnapshot {
        let records = try await tasks()
        return TaskViewSnapshot(tasks: dayPage(on: day, in: records), allTasks: records, projects: TaskProjectSelection.names(in: records))
    }

    public func upcomingDays() async throws -> [UpcomingDay] {
        let records = try await replica.tasks()
        return UpcomingDay.groups(tasks: records, at: now(), calendar: calendar)
    }

    public func task(id: UUID, includingDeleted: Bool = true) async throws -> TaskRecord {
        guard let task = try await tasks().first(where: { $0.id == id }) else {
            throw TaskManagementError.taskNotFound(id)
        }
        guard includingDeleted || task.status != "deleted" else { throw TaskManagementError.taskDeleted(id) }
        return task
    }

    public func create(_ draft: TaskDraft) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { throw TaskManagementError.emptyDescription }
        guard draft.attributes["recur"] == nil, draft.attributes["parent"] == nil,
              draft.attributes["mask"] == nil, draft.attributes["imask"] == nil,
              draft.attributes["rtype"] == nil, draft.attributes["template"] == nil, draft.attributes["last"] == nil,
              draft.attributes["status"] == nil || draft.attributes["status"] == "pending" else {
            throw TaskManagementError.unsupportedTaskKind
        }
        var attributes = try TaskOrganization.normalizedAttributes(draft.attributes)
        let instant = now()
        try validateScheduled(TaskScheduledDate.read(from: attributes, calendar: calendar), at: instant)
        let timestamp = String(Int(instant.timeIntervalSince1970))
        attributes["description"] = description
        attributes["status"] = "pending"
        attributes["entry"] = timestamp
        attributes["modified"] = timestamp
        let task = TaskRecord(id: UUID(), attributes: attributes)
        if TaskManualOrder.plannerGroup(task, calendar: calendar) != nil {
            let records = try await replica.tasks()
            let saved = try await saveOrder(appendingIncoming([task], to: records), context: .day(instant), records: records, creating: task)
            guard let created = saved.first(where: { $0.id == task.id }) else { throw TaskManagementError.storage("The save returned no task.") }
            return created
        }
        let saved = try await replica.create(id: task.id, attributes: attributes)
        await localChangeWasCommitted(tasks: [saved])
        return saved
    }

    public func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        return try await updateTask(id: id, changes: changes)
    }

    func updateTask(id: UUID, changes: TaskAttributePatch, annotationChanges: TaskAttributePatch = [:]) async throws -> TaskRecord {
        let task = try await self.task(id: id)
        guard task.canEdit else { throw TaskManagementError.unsupportedTaskKind }
        let reserved = Set(["uuid", "id", "status", "entry", "modified", "start", "end", "recur", "rtype", "template", "last", "parent", "mask", "imask", "tags", "depends"])
        if let key = changes.keys.sorted().first(where: { reserved.contains($0) || $0.utf8.starts(with: "dep_".utf8) || $0.utf8.starts(with: "annotation_".utf8) }) {
            throw TaskManagementError.reservedAttribute(key)
        }
        guard !changes.isEmpty || !annotationChanges.isEmpty else { return task }
        var patch = changes
        if changes.keys.contains("description") {
            let description = (changes["description"] ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !description.isEmpty else { throw TaskManagementError.emptyDescription }
            patch["description"] = description
        }
        patch = try TaskOrganization.normalizedChanges(patch, original: task.attributes)
        for field in TaskDateField.allCases {
            if let value = patch[field.attribute], value != task.attributes[field.attribute], patch[field.precisionAttribute] == nil,
               task.attributes[field.precisionAttribute] != nil {
                patch.updateValue(nil, forKey: field.precisionAttribute)
            }
        }
        try validateScheduledChange(patch, original: task.attributes, at: now())
        for (key, value) in annotationChanges { patch.updateValue(value, forKey: key) }
        patch["modified"] = String(Int(now().timeIntervalSince1970))
        var edited = task
        for (key, value) in patch { edited.attributes[key] = value }
        if task.status == "pending", let group = TaskManualOrder.plannerGroup(edited, calendar: calendar),
           group != TaskManualOrder.plannerGroup(task, calendar: calendar) {
            let records = try await replica.tasks()
            let ordered = appendingIncoming([edited], to: records)
            if ordered.count > 1 {
                let saved = try await saveOrder(ordered, context: .day(now()), records: records)
                guard let updated = saved.first(where: { $0.id == id }) else { throw TaskManagementError.taskNotFound(id) }
                return updated
            }
            patch[TaskManualOrder.plannerAttribute] = TaskManualOrder.value(group: group, rank: 0)
        }
        if task.isOccurrence { return try await saveOccurrence(task, changes: patch) }
        let saved = try await replica.update(id: id, changes: patch)
        await localChangeWasCommitted(tasks: [saved])
        return saved
    }

    public func complete(id: UUID) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let task = try await self.task(id: id, includingDeleted: false)
        let changes = completionChanges(for: task, at: now())
        if task.isOccurrence {
            return try await saveOccurrence(task, changes: changes, completing: true)
        }
        guard task.canEdit else { throw TaskManagementError.unsupportedTaskKind }
        if task.status == "completed" { return task }
        let saved = try await replica.update(id: id, changes: changes)
        await localChangeWasCommitted(tasks: [saved])
        return saved
    }

    public func reopen(id: UUID) async throws -> TaskRecord {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let task = try await self.task(id: id, includingDeleted: false)
        if task.canComplete { return task }
        guard task.canReopen else { throw TaskManagementError.unsupportedTaskKind }
        let patch: TaskAttributePatch = [
            "status": "pending", "end": nil, TaskCompletionPlacement.attribute: nil,
            "modified": String(Int(now().timeIntervalSince1970))
        ]
        return try await saveTaskMutation(task, changes: patch)
    }

}
