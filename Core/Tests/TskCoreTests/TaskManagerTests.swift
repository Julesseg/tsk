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
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord {
        let task = TaskRecord(id: id, attributes: attributes)
        records[id] = task
        return task
    }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord {
        guard var task = records[id] else { throw TaskManagementError.taskNotFound(id) }
        for (key, value) in changes { task.attributes[key] = value }
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

@Test func editAndCompletePreserveIdentityAndOpaqueAttributes() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1792015200) })
    let original = try await manager.create(TaskDraft(description: "Original", attributes: ["opaque": "keep", "project": "Home"]))
    let edited = try await manager.update(id: original.id, changes: ["description": "  Revised  "])
    #expect(edited.id == original.id)
    #expect(edited.description == "Revised")
    #expect(edited.attributes["opaque"] == "keep")
    let completed = try await manager.complete(id: original.id)
    #expect(completed.status == "completed")
    #expect(completed.attributes["end"] == "1792015200")
    #expect(completed.attributes["modified"] == "1792015200")
    #expect(completed.attributes["project"] == "Home")
    #expect(try await manager.tasks(query: .unfinished).isEmpty)
    #expect(try await manager.tasks(query: .completed) == [completed])
}

@Test func reservedAttributesAndRecurringMutationsAreRejectedWithoutChangingTasks() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica)
    let ordinary = try await manager.create(TaskDraft(description: "Ordinary"))
    await #expect(throws: TaskManagementError.reservedAttribute("status")) {
        try await manager.update(id: ordinary.id, changes: ["status": "deleted"])
    }
    await #expect(throws: TaskManagementError.emptyDescription) {
        try await manager.update(id: ordinary.id, changes: ["description": "  "])
    }
    #expect(try await manager.task(id: ordinary.id) == ordinary)
    let occurrence = try await replica.create(id: UUID(), attributes: ["description": "Occurrence", "status": "pending", "parent": UUID().uuidString])
    await #expect(throws: TaskManagementError.unsupportedTaskKind) {
        try await manager.complete(id: occurrence.id)
    }
    #expect(try await manager.task(id: occurrence.id) == occurrence)
}

@Test func completingAgainPreservesOriginalCompletionTime() async throws {
    let replica = TestReplica()
    let first = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1792015200) })
    let original = try await first.create(TaskDraft(description: "Finish once"))
    let completed = try await first.complete(id: original.id)
    let later = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1792101600) })
    #expect(try await later.complete(id: original.id) == completed)
}

@Test func failedEditAndCompletionRemainFailuresWithOriginalTaskAvailable() async throws {
    let original = TaskRecord(id: UUID(), attributes: ["description": "Original", "status": "pending", "opaque": "retain"])
    let manager = TaskManager(replica: UnwritableReplica(task: original))
    await #expect(throws: TaskManagementError.storage("Disk is full")) {
        try await manager.update(id: original.id, changes: ["description": "Unsaved"])
    }
    await #expect(throws: TaskManagementError.storage("Disk is full")) {
        try await manager.complete(id: original.id)
    }
    #expect(try await manager.task(id: original.id) == original)
    #expect(try await manager.tasks(query: .unfinished) == [original])
}

private struct UnwritableReplica: TaskReplica {
    let task: TaskRecord
    func tasks() async throws -> [TaskRecord] { [task] }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord { throw TaskManagementError.storage("Disk is full") }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord { throw TaskManagementError.storage("Disk is full") }
}
