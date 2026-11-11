#if canImport(AppIntents)
import AppIntents
import Foundation
import TskCore
import TskNative

@available(iOS 16, macOS 13, *)
public enum IntentTaskTagOperation: String, AppEnum {
    case add, remove, replace, clear
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tag operation"
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.add: "Add", .remove: "Remove", .replace: "Replace", .clear: "Clear"]
}

@available(iOS 16, macOS 13, *)
public struct ModifyTaskIntent: AppIntent {
    public static let title: LocalizedStringResource = "Modify Task"
    public static let description = IntentDescription("Modify one task immediately, even offline. Empty inputs keep saved values. Use Clear controls to remove optional fields. All changes save together locally; server synchronization is not required.")
    public static let openAppWhenRun = false
    @Parameter(title: "Task") public var task: IntentTaskEntity
    @Parameter(title: "Description") public var taskDescription: String?
    @Parameter(title: "Project") public var project: String?
    @Parameter(title: "Tags") public var tags: [String]?
    @Parameter(title: "Tag operation", default: .add) public var tagOperation: IntentTaskTagOperation
    @Parameter(title: "Priority") public var priority: IntentTaskPriority?
    @Parameter(title: "Scheduled") public var scheduled: Date?
    @Parameter(title: "Deadline") public var deadline: Date?
    @Parameter(title: "Waiting until") public var waitingUntil: Date?
    @Parameter(title: "Clear project", default: false) public var clearProject: Bool
    @Parameter(title: "Clear priority", default: false) public var clearPriority: Bool
    @Parameter(title: "Clear Scheduled", default: false) public var clearScheduled: Bool
    @Parameter(title: "Clear Deadline", default: false) public var clearDeadline: Bool
    @Parameter(title: "Clear Waiting until", default: false) public var clearWaitingUntil: Bool
    private var directory: URL?

    public static var parameterSummary: some ParameterSummary {
        Summary("Modify \(\.$task)") {
            \.$taskDescription
            \.$project
            \.$tags
            \.$tagOperation
            \.$priority
            \.$scheduled
            \.$deadline
            \.$waitingUntil
            \.$clearProject
            \.$clearPriority
            \.$clearScheduled
            \.$clearDeadline
            \.$clearWaitingUntil
        }
    }

    public init() {}
    public init(task: IntentTaskEntity, description: String? = nil, project: String? = nil, tags: [String]? = nil, tagOperation: IntentTaskTagOperation = .add, priority: IntentTaskPriority? = nil, scheduled: Date? = nil, deadline: Date? = nil, waitingUntil: Date? = nil, clearProject: Bool = false, clearPriority: Bool = false, clearScheduled: Bool = false, clearDeadline: Bool = false, clearWaitingUntil: Bool = false, directory: URL? = nil) {
        self.task = task
        taskDescription = description
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
        self.directory = directory
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<IntentTaskEntity> & ProvidesDialog {
        let input = ModifyTaskInput(description: taskDescription, project: project, tags: tags, tagOperation: TaskTagOperation(rawValue: tagOperation.rawValue)!, priority: priority?.rawValue, scheduled: scheduled, deadline: deadline, waitingUntil: waitingUntil, clearProject: clearProject, clearPriority: clearPriority, clearScheduled: clearScheduled, clearDeadline: clearDeadline, clearWaitingUntil: clearWaitingUntil)
        let location = try directory ?? TaskChampionSession.directory(testName: ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"])
        let manager = try await TaskChampionSession.open(directory: location)
        let saved = try await manager.modifyTask(id: task.id, input: input)
        return .result(value: IntentTaskEntity(saved), dialog: "Saved locally: \(saved.description)")
    }
}
#endif
