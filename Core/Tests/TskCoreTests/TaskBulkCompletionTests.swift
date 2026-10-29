import Foundation
import Testing
import TskCore

@Test func bulkCompletionCombinesSiblingMasksAndDeduplicatesTasks() async throws {
    let parent = TaskRecord(id: UUID(), attributes: ["status": "recurring", "mask": "-W-", "opaque": "e\u{301}"])
    let first = TaskRecord(id: UUID(), attributes: ["status": "pending", "description": "First", "parent": parent.id.uuidString, "imask": "0", "start": "10"])
    let second = TaskRecord(id: UUID(), attributes: ["status": "pending", "description": "Second", "parent": parent.id.uuidString, "imask": "1"])
    let plain = TaskRecord(id: UUID(), attributes: ["status": "pending", "description": "Plain", "opaque": "keep"])
    let replica = OccurrenceReplica(records: [parent, first, second, plain])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    let saved = try await manager.complete(ids: [first.id, second.id, plain.id, first.id])
    #expect(Set(saved.map(\.id)) == [first.id, second.id, plain.id])
    #expect(saved.allSatisfy { $0.status == "completed" && $0.attributes["end"] == "100" && $0.attributes["start"] == nil })
    #expect(try await manager.task(id: parent.id).attributes["mask"] == "++-")
    #expect(try await manager.task(id: parent.id).attributes["opaque"]?.matchesBytes("e\u{301}") == true)
    #expect(try await manager.task(id: plain.id).attributes["opaque"] == "keep")
    #expect(await replica.batches == 1)
}

@Test func bulkCompletionRejectsTheWholeSelectionBeforeAnyWrite() async throws {
    let plain = TaskRecord(id: UUID(), attributes: ["status": "pending", "description": "Plain"])
    let parent = TaskRecord(id: UUID(), attributes: ["status": "recurring", "mask": "--"])
    let child = TaskRecord(id: UUID(), attributes: ["status": "pending", "description": "Bad position", "parent": parent.id.uuidString, "imask": "8"])
    let original = [plain, parent, child]
    let replica = OccurrenceReplica(records: original)
    let manager = TaskManager(replica: replica)
    for ids in [[plain.id, child.id], [plain.id, parent.id], [plain.id, UUID()]] {
        await #expect(throws: (any Error).self) { try await manager.complete(ids: ids) }
        #expect(await replica.records == original)
        #expect(await replica.batches == 0)
    }
}
