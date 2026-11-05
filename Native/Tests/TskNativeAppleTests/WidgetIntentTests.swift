import Foundation
import Testing
import TskCore
import TskNative
#if canImport(AppIntents)
@Test func theWidgetCompletionIntentUsesTheSelectedRegisteredViewAndPublishesSharedChanges() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let app = TaskChampionSession.makeManager(directory: root)
    let saved = try await app.create(TaskDraft(description: "Widget actual AppIntent", attributes: ["opaque": "retain", "project": "Widget"]))
    let custom = try await app.saveView(name: "Widget pending", expression: "project:Widget status:pending")
    let selected = try TaskViewReference(id: TaskViewReference.custom(custom.id).id)
    let widget = try await TaskChampionSession.open(directory: root)
    #expect(try await widget.viewSnapshot(reference: selected).tasks.map(\.id) == [saved.id])
    let before = try await app.changeVersion()
    _ = try await CompleteTaskIntent(task: IntentTaskEntity(saved), directory: root).perform()
    #expect(try await app.changeVersion().tasks != before.tasks)
    #expect(try await widget.viewSnapshot(reference: selected).tasks.isEmpty)
    let completed = try await app.task(id: saved.id)
    #expect(completed.status == "completed")
    #expect(completed.attributes["opaque"] == "retain")
    try await app.deleteView(id: custom.id)
    await #expect(throws: TaskViewError.missingView(custom.id)) { try await widget.viewSnapshot(reference: selected) }
}
#endif
