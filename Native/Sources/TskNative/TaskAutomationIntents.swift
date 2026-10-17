#if canImport(AppIntents)
import AppIntents
import Foundation
import TskCore

@available(iOS 16, macOS 13, *)
public enum IntentTaskDateRole: String, AppEnum {
    case plannedDay, deadline
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task date"
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.plannedDay: "Planned day", .deadline: "Deadline"]
    var coreRole: TaskDateRole { self == .plannedDay ? .planned : .deadline }
}

@available(iOS 16, macOS 13, *)
public struct CompleteTaskIntent: AppIntent {
    public static let title: LocalizedStringResource = "Complete Task"
    public static let description = IntentDescription("Complete a saved task in tsk. The change is saved locally before the action finishes.")
    public static let openAppWhenRun = false
    @Parameter(title: "Task") public var task: IntentTaskEntity
    private var directory: URL?
    public static var parameterSummary: some ParameterSummary { Summary("Complete \(\.$task)") }

    public init() {}
    public init(task: IntentTaskEntity, directory: URL? = nil) {
        self.task = task
        self.directory = directory
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<IntentTaskEntity> & ProvidesDialog {
        let manager = try await IntentTaskSession.open(directory: directory)
        let saved = try await manager.complete(id: task.id)
        return .result(value: IntentTaskEntity(saved), dialog: "Completion saved locally: \(saved.description)")
    }
}

@available(iOS 16, macOS 13, *)
public struct RescheduleTaskIntent: AppIntent {
    public static let title: LocalizedStringResource = "Reschedule Task"
    public static let description = IntentDescription("Change a task's planned day or deadline independently. The other date is preserved.")
    public static let openAppWhenRun = false
    @Parameter(title: "Task") public var task: IntentTaskEntity
    @Parameter(title: "Date role") public var dateRole: IntentTaskDateRole
    @Parameter(title: "New date") public var newDate: Date
    private var directory: URL?
    public static var parameterSummary: some ParameterSummary { Summary("Set \(\.$task) \(\.$dateRole) to \(\.$newDate)") }

    public init() {}
    public init(task: IntentTaskEntity, role: IntentTaskDateRole, date: Date, directory: URL? = nil) {
        self.task = task
        dateRole = role
        newDate = date
        self.directory = directory
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<IntentTaskEntity> & ProvidesDialog {
        let manager = try await IntentTaskSession.open(directory: directory)
        let saved = try await manager.reschedule(id: task.id, role: dateRole.coreRole, to: newDate)
        let dialog: IntentDialog = dateRole == .plannedDay ? "Planned day saved locally: \(saved.description)" : "Deadline saved locally: \(saved.description)"
        return .result(value: IntentTaskEntity(saved), dialog: dialog)
    }
}
#endif
