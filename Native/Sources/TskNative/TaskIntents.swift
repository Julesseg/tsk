#if canImport(AppIntents)
import AppIntents
import Foundation
import TskCore

@available(iOS 16, macOS 13, *)
public struct IntentTaskEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    public static let defaultQuery = IntentTaskQuery()
    public let id: UUID
    @Property(title: "Full UUID") public var uuid: String
    @Property(title: "Description") public var description: String
    @Property(title: "Project") public var project: String?
    @Property(title: "Tags") public var tags: [String]
    @Property(title: "Priority") public var priority: String?
    @Property(title: "Scheduled") public var scheduled: Date?
    @Property(title: "Deadline") public var deadline: Date?
    @Property(title: "Waiting until") public var waitingUntil: Date?
    @Property(title: "Status") public var status: String
    @Property(title: "Open Task URL") public var openTaskURL: URL
    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(description)", subtitle: "\(status.capitalized)")
    }

    public init(_ task: TaskRecord) {
        id = task.id
        uuid = task.id.uuidString
        description = task.description
        project = task.project.isEmpty ? nil : task.project
        tags = task.tags
        priority = task.priority.isEmpty ? nil : task.priority
        scheduled = task.plannedDate
        deadline = task.deadline
        waitingUntil = task.waitUntil
        status = task.status
        openTaskURL = TaskActionResult(task).openTaskURL
    }
}

@available(iOS 16, macOS 13, *)
public struct IntentTaskQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [IntentTaskEntity] {
        let manager = try await IntentTaskSession.open()
        let records = try await manager.tasks()
        return identifiers.compactMap { id in records.first(where: { $0.id == id }).map(IntentTaskEntity.init) }
    }

    public func entities(matching string: String) async throws -> [IntentTaskEntity] {
        let manager = try await IntentTaskSession.open()
        return try await manager.findTasks(FindTasksInput(description: string, status: .all)).map(IntentTaskEntity.init)
    }

    public func suggestedEntities() async throws -> [IntentTaskEntity] {
        let manager = try await IntentTaskSession.open()
        return try await manager.findTasks().map(IntentTaskEntity.init)
    }
}

@available(iOS 16, macOS 13, *)
public enum IntentTaskStatus: String, AppEnum {
    case unfinished, completed, all
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task status"
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .unfinished: "Unfinished", .completed: "Completed", .all: "All"
    ]
    var selection: FindTaskStatus { FindTaskStatus(rawValue: rawValue)! }
}

@available(iOS 16, macOS 13, *)
public enum IntentTaskPriority: String, AppEnum {
    case high = "H", medium = "M", low = "L", none = ""
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task priority"
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.high: "High", .medium: "Medium", .low: "Low", .none: "No priority"]
}

@available(iOS 16, macOS 13, *)
public enum IntentTaskSort: String, AppEnum {
    case newest = "created-desc", oldest = "created-asc", description = "description-asc"
    case scheduled = "scheduled-asc", deadline = "deadline-asc", waitingUntil = "waiting-until-asc", priority = "priority-desc"
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task sort"
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .newest: "Newest created first", .oldest: "Oldest created first", .description: "Description (UTF-8 order)",
        .scheduled: "Scheduled (earliest first)", .deadline: "Deadline (earliest first)",
        .waitingUntil: "Waiting until (earliest first)", .priority: "Priority (High first)"
    ]
    var selection: FindTaskSort { FindTaskSort(rawValue: rawValue)! }
}

@available(iOS 16, macOS 13, *)
public struct FindTasksIntent: AppIntent {
    public static let title: LocalizedStringResource = "Find Tasks"
    public static let description = IntentDescription("Find saved tasks using named filters. Every filter must match. Date bounds are inclusive; missing dates do not match a supplied range. Returns all matches unless Limit is set. Sort ties use newest created, then UUID; missing sort dates come last. All excludes deleted tasks.")
    public static let openAppWhenRun = false
    @Parameter(title: "Description contains", default: "") public var searchText: String
    @Parameter(title: "Project (exact)") public var project: String?
    @Parameter(title: "Tags (all)") public var tags: [String]?
    @Parameter(title: "Status", default: .unfinished) public var status: IntentTaskStatus
    @Parameter(title: "Priority") public var priority: IntentTaskPriority?
    @Parameter(title: "Scheduled from (inclusive)") public var scheduledFrom: Date?
    @Parameter(title: "Scheduled through (inclusive)") public var scheduledThrough: Date?
    @Parameter(title: "Deadline from (inclusive)") public var deadlineFrom: Date?
    @Parameter(title: "Deadline through (inclusive)") public var deadlineThrough: Date?
    @Parameter(title: "Waiting until from (inclusive)") public var waitingUntilFrom: Date?
    @Parameter(title: "Waiting until through (inclusive)") public var waitingUntilThrough: Date?
    @Parameter(title: "Sort", default: .newest) public var sort: IntentTaskSort
    @Parameter(title: "Limit") public var limit: Int?
    @Parameter(title: "Offset", default: 0) public var offset: Int
    private var directory: URL?

    public static var parameterSummary: some ParameterSummary {
        Summary("Find \(\.$status) tasks containing \(\.$searchText)") {
            \.$project
            \.$tags
            \.$priority
            \.$scheduledFrom
            \.$scheduledThrough
            \.$deadlineFrom
            \.$deadlineThrough
            \.$waitingUntilFrom
            \.$waitingUntilThrough
            \.$sort
            \.$limit
            \.$offset
        }
    }

    public init() {}
    public init(searchText: String = "", project: String? = nil, tags: [String] = [], status: IntentTaskStatus = .unfinished, priority: IntentTaskPriority? = nil, scheduledFrom: Date? = nil, scheduledThrough: Date? = nil, deadlineFrom: Date? = nil, deadlineThrough: Date? = nil, waitingUntilFrom: Date? = nil, waitingUntilThrough: Date? = nil, sort: IntentTaskSort = .newest, limit: Int? = nil, offset: Int = 0, directory: URL? = nil) {
        self.searchText = searchText
        self.project = project
        self.tags = tags
        self.status = status
        self.priority = priority
        self.scheduledFrom = scheduledFrom
        self.scheduledThrough = scheduledThrough
        self.deadlineFrom = deadlineFrom
        self.deadlineThrough = deadlineThrough
        self.waitingUntilFrom = waitingUntilFrom
        self.waitingUntilThrough = waitingUntilThrough
        self.sort = sort
        self.limit = limit
        self.offset = offset
        self.directory = directory
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[IntentTaskEntity]> & ProvidesDialog {
        let input = FindTasksInput(description: searchText, project: project, tags: tags ?? [], status: status.selection, priority: priority?.rawValue,
                                   scheduled: TaskDateRange(from: scheduledFrom, through: scheduledThrough),
                                   deadline: TaskDateRange(from: deadlineFrom, through: deadlineThrough),
                                   waitingUntil: TaskDateRange(from: waitingUntilFrom, through: waitingUntilThrough), sort: sort.selection, limit: limit, offset: offset)
        try input.validate()
        let manager = try await IntentTaskSession.open(directory: directory)
        let tasks = try await manager.findTasks(input).map(IntentTaskEntity.init)
        return .result(value: tasks, dialog: "Found \(tasks.count) tasks.")
    }
}

@available(iOS 16, macOS 13, *)
enum IntentTaskSession {
    static func open(directory: URL? = nil) async throws -> TaskManager {
        let location = try directory ?? TaskChampionSession.directory(testName: ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"])
        return try await TaskChampionSession.open(directory: location)
    }
}
#endif
