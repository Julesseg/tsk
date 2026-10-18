import Foundation
import Testing
import TskCore

@Test func findingTasksReturnsPersistentIdentitiesAndHonorsStatusWithoutChangingAttributes() async throws {
    let manager = TaskManager(replica: TestReplica())
    let first = try await manager.create(TaskDraft(description: "Réserver le train", attributes: ["opaque": "unchanged"]))
    let second = try await manager.create(TaskDraft(description: "Buy train tickets"))
    _ = try await manager.complete(id: second.id)
    #expect(try await manager.findTasks(matching: "TRAIN", query: .unfinished) == [first])
    #expect(try await manager.findTasks(matching: "train", query: .completed).map(\.id) == [second.id])
    #expect(try await manager.findTasks(matching: "  ", query: .all).count == 2)
    #expect(try await manager.findTasks(matching: "missing", query: .all).isEmpty)
    #expect(try await manager.task(id: first.id) == first)
}
