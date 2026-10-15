import Foundation
import Testing
@testable import TskCore

@Test func startAndStopKeepIndependentDatesAndOpaqueFieldsAndPreserveOriginalStartOnRepeat() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1792144800) })
    let original = try await manager.create(TaskDraft(description: "Work now", attributes: ["scheduled": "1792108800", "due": "1792220400", "wait": "1792310400", "opaque": "retain", "café": "first", "cafe\u{301}": "second"]))
    let started = try await manager.start(id: original.id)
    #expect(started.isActive)
    #expect(started.attributes["start"] == "1792144800")
    #expect(started.startedAt == Date(timeIntervalSince1970: 1792144800))
    #expect(started.status == "pending")
    for key in ["scheduled", "due", "wait", "opaque", "café", "cafe\u{301}"] { #expect(started.attributes[key] == original.attributes[key]) }
    let later = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1792144900) })
    #expect(try await later.start(id: original.id) == started)
    #expect(try await later.tasks(filter: "+ACTIVE").map(\.id) == [original.id])
    let stopped = try await later.stop(id: original.id)
    #expect(!stopped.isActive)
    #expect(stopped.attributes["start"] == nil)
    #expect(stopped.attributes["modified"] == "1792144900")
    #expect(stopped.attributes["wait"] == original.attributes["wait"])
    #expect(try await later.stop(id: original.id) == stopped)
    #expect(try await later.tasks(filter: "+ACTIVE").isEmpty)
    #expect(stopped.id == original.id)
}

@Test func activityCannotReopenCompletedTasksOrBypassDedicatedStartField() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1792144800) })
    let original = try await manager.create(TaskDraft(description: "Done after active", attributes: ["opaque": "keep"]))
    await #expect(throws: TaskManagementError.reservedAttribute("start")) { try await manager.update(id: original.id, changes: ["start": "100"]) }
    _ = try await manager.start(id: original.id)
    let completed = try await manager.complete(id: original.id)
    #expect(completed.status == "completed")
    #expect(!completed.isActive)
    #expect(completed.attributes["start"] == nil)
    #expect(completed.attributes["end"] == "1792144800")
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await manager.start(id: original.id) }
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await manager.stop(id: original.id) }
    #expect(try await manager.task(id: original.id) == completed)
}

@Test func activityForOccurrencesUsesAtomicSeriesValidationAndCompletionClearsStart() async throws {
    let parent = UUID(), child = UUID(), sibling = UUID()
    let template = TaskRecord(id: parent, attributes: ["status": "recurring", "mask": "W-", "opaque": "parent"])
    let source = TaskRecord(id: child, attributes: ["description": "Occurrence", "status": "pending", "parent": parent.uuidString, "imask": "0", "due": "400", "scheduled": "200", "wait": "300", "opaque": "child"])
    let other = TaskRecord(id: sibling, attributes: ["status": "pending", "parent": parent.uuidString, "imask": "1"])
    let replica = OccurrenceReplica(records: [template, source, other])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    let active = try await manager.start(id: child)
    #expect(active.attributes["start"] == "100")
    #expect(try await manager.task(id: parent) == template)
    #expect(try await manager.task(id: sibling) == other)
    let stopped = try await manager.stop(id: child)
    #expect(stopped.attributes["start"] == nil)
    #expect(stopped.attributes["wait"] == "300")
    _ = try await manager.start(id: child)
    let completed = try await manager.complete(id: child)
    #expect(completed.attributes["start"] == nil)
    #expect(try await manager.task(id: parent).attributes["mask"] == "+-")
    #expect(await replica.batches == 4)
    #expect(try await manager.task(id: sibling) == other)
    await #expect(throws: TaskManagementError.unsupportedTaskKind) { try await manager.start(id: child) }
}

@Test func failedActivitySaveAndMalformedOccurrenceLeaveAllRawAttributesUnchanged() async throws {
    let task = TaskRecord(id: UUID(), attributes: ["status": "pending", "description": "No write", "opaque": "retain"])
    let manager = TaskManager(replica: ActivityUnwritableReplica(record: task))
    await #expect(throws: (any Error).self) { try await manager.start(id: task.id) }
    #expect(try await manager.task(id: task.id) == task)
    let missing = UUID()
    let child = TaskRecord(id: UUID(), attributes: ["status": "pending", "parent": missing.uuidString, "imask": "0", "start": "bad timestamp"])
    let replica = OccurrenceReplica(records: [child])
    let occurrenceManager = TaskManager(replica: replica)
    await #expect(throws: (any Error).self) { try await occurrenceManager.stop(id: child.id) }
    #expect(try await occurrenceManager.task(id: child.id) == child)
    #expect(await replica.batches == 0)
}

private struct ActivityUnwritableReplica: TaskReplica {
    let record: TaskRecord
    func tasks() async throws -> [TaskRecord] { [record] }
    func create(id: UUID, attributes: TaskAttributes) async throws -> TaskRecord { throw TaskManagementError.storage("No write") }
    func update(id: UUID, changes: TaskAttributePatch) async throws -> TaskRecord { throw TaskManagementError.storage("No write") }
}

@Test func activeMarkersRemainIndependentAcrossTasksAndRawTimestampsCanBeStoppedExplicitly() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 100) })
    let first = try await manager.create(TaskDraft(description: "First"))
    let second = try await manager.create(TaskDraft(description: "Second"))
    _ = try await manager.start(id: first.id)
    _ = try await manager.start(id: second.id)
    #expect(Set(try await manager.tasks(filter: "+ACTIVE").map(\.id)) == [first.id, second.id])
    let imported = try await manager.create(TaskDraft(description: "Preserved raw marker", attributes: ["start": "unrecognized", "opaque": "keep"]))
    #expect(imported.isActive)
    #expect(imported.startedAt == nil)
    #expect(try await manager.start(id: imported.id) == imported)
    let cleared = try await manager.stop(id: imported.id)
    #expect(cleared.attributes["start"] == nil)
    #expect(cleared.attributes["opaque"] == "keep")
}
