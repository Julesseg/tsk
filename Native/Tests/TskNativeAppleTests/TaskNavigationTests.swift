#if canImport(AppIntents)
import AppIntents
import Foundation
import Testing
import TskCore
import TskNative

@available(macOS 15, iOS 18, *)
@MainActor @Test func navigationPickerUsesDurableViewsAndStableIdentityWithoutChangingFavorites() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = try await TaskChampionSession.open(directory: directory)
    let navigation = ForegroundTaskNavigation()
    navigation.connect { action in
        switch action {
        case .openTask(let id): _ = try await manager.navigationDestination(taskID: id)
        case .openView(let view): _ = try await manager.navigationDestination(view: view)
        case .add: Issue.record("Background action reached navigation")
        }
    }
    let task = try await manager.create(TaskDraft(description: "Current task", attributes: ["project": "Work.Travel"]))
    let saved = try await manager.saveView(name: "Original view", expression: "+PENDING")
    let workspaceStore = LocalWorkspaceViewStore(directory: directory)
    var favorites = WorkspaceViews(customIDs: [saved.id])
    try favorites.deactivate(.today)
    try workspaceStore.save(favorites)
    let query = IntentTaskViewQuery(directory: directory)
    let initial = try await query.suggestedEntities()
    #expect(initial.map(\.name) == ["Today", "Upcoming", "All unfinished", "Done", "Projects", "Work.Travel", "Original view"])
    let identity = try #require(initial.last?.id)
    let stale = IntentTaskEntity(task)
    _ = try await manager.update(id: task.id, changes: ["description": "Fresh task"])
    _ = try await manager.saveView(id: saved.id, name: "Renamed view", expression: "project:Work.Travel")
    let renamed = try #require(try await query.entities(for: [identity]).first)
    #expect(renamed.name == "Renamed view")
    #expect(try renamed.view == .saved(saved.id))
    _ = try await OpenTaskViewIntent(view: renamed, navigation: navigation).perform()
    _ = try await OpenTaskIntent(task: stale, navigation: navigation).perform()
    _ = try await manager.complete(id: task.id)
    _ = try await OpenTaskIntent(task: stale, navigation: navigation).perform()
    #expect(try await manager.navigationDestination(taskID: stale.id).task?.description == "Fresh task")
    #expect(try workspaceStore.load(customIDs: [saved.id]) == favorites)
    #expect(try await manager.savedViews().map(\.name) == ["Renamed view"])
    try await manager.deleteView(id: saved.id)
    #expect(try await query.entities(for: [identity]).isEmpty)
    await #expect(throws: TaskViewError.missingView(saved.id)) { try await OpenTaskViewIntent(view: renamed, navigation: navigation).perform() }
    let missing = IntentTaskEntity(TaskRecord(id: UUID(), attributes: ["description": "Missing", "status": "pending"]))
    await #expect(throws: TaskManagementError.taskNotFound(missing.id)) { try await OpenTaskIntent(task: missing, navigation: navigation).perform() }
    navigation.connect { _ in throw TaskActionError.navigationFailed("Retained invalid draft") }
    await #expect(throws: TaskActionError.navigationFailed("Retained invalid draft")) { try await OpenTaskIntent(task: stale, navigation: navigation).perform() }
    #expect(OpenTaskIntent.openAppWhenRun && OpenTaskViewIntent.openAppWhenRun)
    #expect(!CompleteTaskIntent.openAppWhenRun && !RescheduleTaskIntent.openAppWhenRun)
}
#endif
