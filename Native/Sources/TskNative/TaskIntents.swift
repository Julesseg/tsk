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
        return try await manager.findTasks(matching: string, query: .all).map(IntentTaskEntity.init)
    }

    public func suggestedEntities() async throws -> [IntentTaskEntity] {
        let manager = try await IntentTaskSession.open()
        return try await manager.tasks(query: .unfinished).map(IntentTaskEntity.init)
    }
}

@available(iOS 16, macOS 13, *)
public enum IntentTaskStatus: String, AppEnum {
    case unfinished, completed, all
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task status"
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .unfinished: "Unfinished", .completed: "Completed", .all: "All"
    ]
    var query: TaskQuery {
        switch self { case .unfinished: .unfinished; case .completed: .completed; case .all: .all }
    }
}

@available(iOS 16, macOS 13, *)
public struct FindTasksIntent: AppIntent {
    public static let title: LocalizedStringResource = "Find Tasks"
    public static let description = IntentDescription("Find saved tsk tasks by description and status.")
    public static let openAppWhenRun = false
    @Parameter(title: "Description contains", default: "") public var searchText: String
    @Parameter(title: "Status", default: .unfinished) public var status: IntentTaskStatus
    private var directory: URL?
    public static var parameterSummary: some ParameterSummary { Summary("Find \(\.$status) tasks containing \(\.$searchText)") }

    public init() {}
    public init(searchText: String = "", status: IntentTaskStatus = .unfinished, directory: URL? = nil) {
        self.searchText = searchText
        self.status = status
        self.directory = directory
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[IntentTaskEntity]> & ProvidesDialog {
        let manager = try await IntentTaskSession.open(directory: directory)
        let tasks = try await manager.findTasks(matching: searchText, query: status.query).map(IntentTaskEntity.init)
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
