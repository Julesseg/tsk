import Foundation
import Testing
import TskCore
import TskNative

@Test func rawSavedViewsPersistEditDeleteAndRejectInvalidExpressionsWithoutLosingDefinition() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    func manager() -> TaskManager {
        TaskManager(replica: TaskChampionReplica(directory: directory.appendingPathComponent("replica")), viewDefinitions: LocalTaskViewStore(directory: directory.appendingPathComponent("views")))
    }
    let first = manager()
    let task = try await first.create(TaskDraft(description: "Saved view task", attributes: ["project": "Work", "opaque": "retain"]))
    let saved = try await first.saveView(name: "My work", expression: "project.is:Work")
    let reopened = manager()
    #expect(try await reopened.savedViews() == [saved])
    #expect(try await reopened.tasks(filter: saved.expression).map(\.id) == [task.id])
    await #expect(throws: TaskFilterError.unknownAttribute("missing")) {
        try await reopened.saveView(id: saved.id, name: "Broken", expression: "missing:Work")
    }
    #expect(try await reopened.savedViews() == [saved])
    let edited = try await reopened.saveView(id: saved.id, name: "Completed work", expression: "status:completed")
    #expect(edited.id == saved.id)
    #expect(try await manager().savedViews() == [edited])
    _ = try await reopened.complete(id: task.id)
    #expect(try await reopened.tasks(filter: edited.expression).map(\.id) == [task.id])
    #expect(try await reopened.task(id: task.id).attributes["opaque"] == "retain")
    try await reopened.deleteView(id: saved.id)
    #expect(try await manager().savedViews().isEmpty)
}
