#if canImport(AppIntents)
import AppIntents
import Foundation
import TskCore
import TskNative

@available(iOS 16, macOS 13, *)
public struct AddTaskIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Task"
    public static let description = IntentDescription("Add one task immediately to durable local storage, even offline. Success does not require server synchronization.")
    public static let openAppWhenRun = false
    @Parameter(title: "Description") public var taskDescription: String
    @Parameter(title: "Project") public var project: String?
    @Parameter(title: "Tags") public var tags: [String]?
    @Parameter(title: "Priority") public var priority: IntentTaskPriority?
    @Parameter(title: "Scheduled") public var scheduled: Date?
    @Parameter(title: "Deadline") public var deadline: Date?
    @Parameter(title: "Waiting until") public var waitingUntil: Date?
    private var directory: URL?

    public static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$taskDescription)") {
            \.$project
            \.$tags
            \.$priority
            \.$scheduled
            \.$deadline
            \.$waitingUntil
        }
    }

    public init() {}
    public init(description: String, project: String? = nil, tags: [String] = [], priority: IntentTaskPriority? = nil, scheduled: Date? = nil, deadline: Date? = nil, waitingUntil: Date? = nil, directory: URL? = nil) {
        taskDescription = description
        self.project = project
        self.tags = tags
        self.priority = priority
        self.scheduled = scheduled
        self.deadline = deadline
        self.waitingUntil = waitingUntil
        self.directory = directory
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<IntentTaskEntity> & ProvidesDialog {
        let input = AddTaskInput(description: taskDescription, project: project, tags: tags ?? [], priority: priority?.rawValue, scheduled: scheduled, deadline: deadline, waitingUntil: waitingUntil)
        _ = try input.validatedDraft()
        let location = try directory ?? TaskChampionSession.directory(testName: ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"])
        let manager = try await TaskChampionSession.open(directory: location)
        let saved = try await manager.addTask(input)
        return .result(value: IntentTaskEntity(saved), dialog: "Saved locally: \(saved.description)")
    }
}
#endif
