import Foundation
import Testing
import TskCore

@Test func registeredViewsReuseTodayProjectsAndCurrentSavedExpressionsWithoutHiddenPredicates() async throws {
    let manager = TaskManager(replica: TestReplica(), viewDefinitions: RegistryViewStore())
    let task = try await manager.create(TaskDraft(description: "Registered task", attributes: ["project": "Café"]))
    _ = try await manager.create(TaskDraft(description: "Other spelling", attributes: ["project": "Cafe\u{301}"]))
    _ = try await manager.complete(id: task.id)
    let saved = try await manager.saveView(name: "Completed custom", expression: "project.is:Café")
    let views = try await manager.registeredViews()
    #expect(views.contains { $0.reference == .query(.today) })
    #expect(views.contains { $0.reference == .project(UTF8String("Café")) })
    #expect(views.contains { $0.reference == .project(UTF8String("Cafe\u{301}")) })
    #expect(try await manager.viewSnapshot(reference: .custom(saved.id)).tasks.map(\.id) == [task.id])
    _ = try await manager.saveView(id: saved.id, name: saved.name, expression: "status:pending")
    #expect(try await manager.viewSnapshot(reference: .custom(saved.id)).tasks.map(\.id) != [task.id])
    try await manager.deleteView(id: saved.id)
    await #expect(throws: TaskViewError.missingView(saved.id)) { try await manager.viewSnapshot(reference: .custom(saved.id)) }
}

private actor RegistryViewStore: TaskViewDefinitionsStore {
    var views: [SavedTaskView] = []
    func load() -> [SavedTaskView] { views }
    func save(_ definitions: [SavedTaskView]) { views = definitions }
}
