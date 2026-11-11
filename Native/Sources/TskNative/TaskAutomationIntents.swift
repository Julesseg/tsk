#if canImport(AppIntents)
import AppIntents
import Foundation
import TskCore

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

#endif
