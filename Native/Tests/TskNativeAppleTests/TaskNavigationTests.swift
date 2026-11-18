#if canImport(AppIntents)
import AppIntents
import Foundation
import Testing
import TskCore
import TskNative

@available(macOS 15, iOS 18, *)
@MainActor @Test func navigationPickerUsesPlannerAndExactProjects() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = try await TaskChampionSession.open(directory: directory)
    let navigation = ForegroundTaskNavigation()
    navigation.connect { action in
        switch action {
        case .openTask(let id): _ = try await manager.navigationDestination(taskID: id)
        case .openView(let view): _ = try await manager.navigationDestination(view: view)
        case .add, .find, .modify, .complete, .delete: Issue.record("Background action reached navigation")
        }
    }
    let task = try await manager.create(TaskDraft(description: "Current task", attributes: ["project": "Work.Travel"]))
    let query = IntentTaskViewQuery(directory: directory)
    let initial = try await query.suggestedEntities()
    #expect(initial.map(\.name) == ["Today", "Inbox", "Projects", "Work.Travel"])
    let identity = try #require(initial.last?.id)
    let stale = IntentTaskEntity(task)
    _ = try await manager.update(id: task.id, changes: ["description": "Fresh task"])
    let selected = try #require(try await query.entities(for: [identity]).first)
    #expect(try selected.view == .project("Work.Travel"))
    _ = try await OpenTaskViewIntent(view: selected, navigation: navigation).perform()
    _ = try await OpenTaskIntent(task: stale, navigation: navigation).perform()
    _ = try await manager.complete(id: task.id)
    _ = try await OpenTaskIntent(task: stale, navigation: navigation).perform()
    #expect(try await manager.navigationDestination(taskID: stale.id).task?.description == "Fresh task")
    let missing = IntentTaskEntity(TaskRecord(id: UUID(), attributes: ["description": "Missing", "status": "pending"]))
    await #expect(throws: TaskManagementError.taskNotFound(missing.id)) { try await OpenTaskIntent(task: missing, navigation: navigation).perform() }
    navigation.connect { _ in throw TaskActionError.navigationFailed("Retained invalid draft") }
    await #expect(throws: TaskActionError.navigationFailed("Retained invalid draft")) { try await OpenTaskIntent(task: stale, navigation: navigation).perform() }
    for action in [TaskActionURL.find(FindTasksInput()), .modify(stale.id, ModifyTaskInput()), .complete(stale.id), .delete(stale.id)] {
        await #expect(throws: TaskActionError.invalidInput("Data actions do not use foreground navigation.")) {
            try await navigation.open(action)
        }
    }
    #expect(OpenTaskIntent.openAppWhenRun && OpenTaskViewIntent.openAppWhenRun)
    #expect(!CompleteTaskIntent.openAppWhenRun && !ModifyTaskIntent.openAppWhenRun)
}
#endif
