#if canImport(AppIntents)
import AppIntents
import Foundation
import TskCore

@available(iOS 16, macOS 13, *)
public struct IntentTaskEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    public static let defaultQuery = IntentTaskQuery()
    public let id: UUID
    public let description: String
    public let status: String
    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(description)", subtitle: "\(status.capitalized)")
    }

    public init(_ task: TaskRecord) {
        id = task.id
        description = task.description
        status = task.status
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
public struct CreateTaskIntent: AppIntent {
    public static let title: LocalizedStringResource = "Create Task"
    public static let description = IntentDescription("Save a task in tsk. Changes synchronize when a connection is available.")
    public static let openAppWhenRun = false
    @Parameter(title: "Description") public var taskDescription: String
    @Parameter(title: "Project") public var project: String?
    private var directory: URL?
    public static var parameterSummary: some ParameterSummary { Summary("Create \(\.$taskDescription)") { \.$project } }

    public init() {}
    public init(description: String, project: String? = nil, directory: URL? = nil) {
        taskDescription = description
        self.project = project
        self.directory = directory
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<IntentTaskEntity> & ProvidesDialog {
        let manager = try await IntentTaskSession.open(directory: directory)
        var attributes: TaskAttributes = [:]
        if let project { attributes["project"] = project }
        let task = try await manager.create(TaskDraft(description: taskDescription, attributes: attributes))
        return .result(value: IntentTaskEntity(task), dialog: "Saved locally: \(task.description)")
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
private enum IntentTaskSession {
    static func open(directory: URL? = nil) async throws -> TaskManager {
        let location = try directory ?? TaskChampionSession.directory(testName: ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"])
        return try await TaskChampionSession.open(directory: location)
    }
}
#endif
