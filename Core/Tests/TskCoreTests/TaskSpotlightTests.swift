import Foundation
import Testing
@testable import TskCore

@Test func spotlightIndexesOnlyPendingTasksWithStableIdentityAndNeverChangesRawFields() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica)
    let original = try await manager.create(TaskDraft(description: "Find café task", attributes: ["project": "Work.Client", "tag_focus": "", "opaque": "preserve", "scheduled": "1792108800", "due": "1792396800", "wait": "2000000000"]))
    let completed = try await manager.create(TaskDraft(description: "Finished"))
    _ = try await manager.complete(id: completed.id)
    let index = TestSpotlightIndex(namespace: "fixture-owned")
    #expect(try await manager.reconcileSpotlight(using: index) == 1)
    let item = try #require(await index.items.first)
    #expect(item.identifier == "fixture-owned/task/" + original.id.uuidString.lowercased())
    #expect(item.title == "Find café task")
    #expect(item.summary.contains("Work.Client") && item.summary.contains("focus"))
    #expect(!item.summary.contains("preserve"))
    #expect(try await manager.task(id: original.id) == original)
    _ = try await manager.update(id: original.id, changes: ["description": "Revised title"])
    #expect(try await manager.reconcileSpotlight(using: index) == 1)
    #expect(await index.items.first?.identifier == item.identifier)
    #expect(await index.items.first?.title == "Revised title")
    _ = try await manager.complete(id: original.id)
    #expect(try await manager.reconcileSpotlight(using: index) == 0)
    #expect(await index.items.isEmpty)
}

actor TestSpotlightIndex: TaskSpotlightIndex {
    nonisolated let namespace: String
    var items: [TaskSpotlightItem] = []
    init(namespace: String) { self.namespace = namespace }
    func replace(_ items: [TaskSpotlightItem]) { self.items = items }
}

@Test func spotlightStaleLinksResolveExactCurrentUUIDOrReportUnavailable() async throws {
    let replica = TestReplica(), manager = TaskManager(replica: TestReplica())
    let current = TaskManager(replica: replica)
    let first = try await current.create(TaskDraft(description: "Identical title"))
    let other = try await current.create(TaskDraft(description: "Identical title"))
    let identifier = TaskSpotlightItem.identifier(for: first.id, namespace: "owned")
    _ = try await current.complete(id: first.id)
    #expect(try await current.resolveSpotlight(identifier: identifier, namespace: "owned").status == "completed")
    _ = try await replica.update(id: first.id, changes: ["status": "deleted"])
    await #expect(throws: TaskSpotlightError.unavailable(first.id)) { try await current.resolveSpotlight(identifier: identifier, namespace: "owned") }
    #expect(try await current.task(id: other.id).status == "pending")
    await #expect(throws: TaskSpotlightError.invalidIdentifier) { try await current.resolveSpotlight(identifier: identifier, namespace: "foreign") }
    await #expect(throws: TaskSpotlightError.unavailable(first.id)) { try await manager.resolveSpotlight(identifier: identifier, namespace: "owned") }
}

@Test func spotlightReconciliationPropagatesIndexErrorsWithoutChangingSavedTasks() async throws {
    let manager = TaskManager(replica: TestReplica())
    let task = try await manager.create(TaskDraft(description: "Saved despite index error"))
    await #expect(throws: (any Error).self) { try await manager.reconcileSpotlight(using: FailedSpotlightIndex()) }
    #expect(try await manager.task(id: task.id) == task)
}
private struct FailedSpotlightIndex: TaskSpotlightIndex {
    let namespace = "owned"
    func replace(_ items: [TaskSpotlightItem]) throws { throw CocoaError(.fileWriteUnknown) }
}
