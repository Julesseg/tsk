import Foundation
import Testing
@testable import TskCore

@Test func occurrenceCompletionAtomicallyPreservesSeries() async throws {
    let parent = UUID(), child = UUID(), sibling = UUID()
    let original = TaskRecord(id: parent, attributes: ["status": "recurring", "recur": "daily", "due": "2000000000", "mask": "--", "opaque": "keep"])
    let occurrence = TaskRecord(id: child, attributes: ["status": "pending", "description": "first", "parent": parent.uuidString, "imask": "0", "opaque": "child"])
    let other = TaskRecord(id: sibling, attributes: ["status": "pending", "parent": parent.uuidString, "imask": "1"])
    let replica = OccurrenceReplica(records: [original, occurrence, other])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    let edited = try await manager.update(id: child, changes: ["description": "only this occurrence"])
    #expect(edited.attributes["parent"] == parent.uuidString)
    let completed = try await manager.complete(id: child)
    #expect(completed.status == "completed")
    #expect(completed.attributes["end"] == "100")
    let records = try await manager.tasks()
    #expect(records.first { $0.id == parent }?.attributes["mask"] == "+-")
    #expect(records.first { $0.id == parent }?.attributes["opaque"] == "keep")
    #expect(records.first { $0.id == sibling } == other)
    #expect(try await manager.complete(id: child) == completed)
    #expect(await replica.batches == 2)
}

@Test func malformedOccurrenceNeverWrites() async throws {
    let parent = UUID(), child = UUID()
    for mask in ["", "?", "+", "--"] {
        let records = [TaskRecord(id: parent, attributes: ["status": "recurring", "mask": mask]), TaskRecord(id: child, attributes: ["status": "pending", "parent": parent.uuidString, "imask": "9"])]
        let replica = OccurrenceReplica(records: records)
        let manager = TaskManager(replica: replica)
        await #expect(throws: (any Error).self) { try await manager.complete(id: child) }
        #expect(try await replica.tasks() == records)
        #expect(await replica.batches == 0)
    }
}

actor OccurrenceReplica: TaskAtomicMutatingReplica {
    var records: [TaskRecord]
    var batches = 0
    init(records: [TaskRecord]) { self.records = records }
    func tasks() -> [TaskRecord] { records }
    func create(id: UUID, attributes: TaskAttributes) throws -> TaskRecord { throw TaskManagementError.storage("Unexpected create") }
    func update(id: UUID, changes: TaskAttributePatch) throws -> TaskRecord { throw TaskManagementError.storage("Sequential update forbidden") }
    func updateAtomically(_ updates: [TaskAtomicUpdate]) throws -> [TaskRecord] {
        for update in updates { guard records.first(where: { $0.id == update.id })?.attributes == update.expected else { throw TaskManagementError.storage("Conflict") } }
        batches += 1
        return updates.map { update in
            let index = records.firstIndex { $0.id == update.id }!
            for (key, value) in update.changes { records[index].attributes[key] = value }
            return records[index]
        }
    }
}
