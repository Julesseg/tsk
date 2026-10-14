import Foundation
import Testing
@testable import TskCore

@Test func captureDraftPreservesUnknownAttributesAndValidatesBeforeSaving() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica)
    await #expect(throws: TaskManagementError.emptyDescription) {
        try await manager.create(TaskDraft(description: "  "))
    }
    #expect(try await manager.tasks().isEmpty)
    let created = try await manager.create(TaskDraft(description: "Buy milk", attributes: ["customField": "opaque value"]))
    #expect(created.attributes["customField"] == "opaque value")
    #expect(created.attributes["status"] == "pending")
    #expect(try await manager.task(id: created.id) == created)
}

actor TestReplica: TaskReplica {
    var records: [UUID: TaskRecord] = [:]
    func tasks() async throws -> [TaskRecord] { Array(records.values) }
    func create(id: UUID, attributes: [String: String]) async throws -> TaskRecord {
        let task = TaskRecord(id: id, attributes: attributes)
        records[id] = task
        return task
    }
}

@Test func ordinaryCaptureRefusesRecurringTaskWithoutCreatingAnything() async throws {
    let manager = TaskManager(replica: TestReplica())
    await #expect(throws: TaskManagementError.unsupportedTaskKind) {
        try await manager.create(TaskDraft(description: "Series", attributes: ["recur": "daily"]))
    }
    #expect(try await manager.tasks().isEmpty)
}
