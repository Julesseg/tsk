import Foundation
import Testing
@testable import TskCore

@Test func seriesMetadataPreviewDoesNotWriteAndSavePreservesHistoryAndUnrelatedFields() async throws {
    let parent = UUID(), future = UUID(), past = UUID(), completed = UUID()
    let template = TaskRecord(id: parent, attributes: ["status": "recurring", "description": "Original", "due": "200", "recur": "weekly", "mask": "---+", "opaque": "parent", "annotation_1": "original note", "tag_old": ""])
    let upcoming = TaskRecord(id: future, attributes: ["status": "pending", "description": "Original", "parent": parent.uuidString, "imask": "1", "due": "200", "opaque": "child", "tag_personal": "", "annotation_7": "personal note"])
    let overdue = TaskRecord(id: past, attributes: ["status": "pending", "parent": parent.uuidString, "imask": "0", "due": "50", "description": "Overdue"])
    let history = TaskRecord(id: completed, attributes: ["status": "completed", "parent": parent.uuidString, "imask": "3", "due": "300", "description": "History", "end": "40"])
    let replica = OccurrenceReplica(records: [template, upcoming, overdue, history])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    let preview = try await manager.previewSeriesMetadata(id: parent, changes: ["description": "Revised", "project": "Work", "tag_old": nil, "tag_new": "", "priority": "H", "annotation_1": "revised note"], addingAnnotation: "New series note")
    #expect(preview.affected.map(\.id) == [future])
    #expect(await replica.batches == 0)
    #expect(try await manager.task(id: future) == upcoming)
    _ = try await manager.applySeriesMetadata(preview)
    #expect(await replica.batches == 1)
    let saved = try await manager.task(id: future)
    #expect(saved.description == "Revised")
    #expect(saved.attributes["parent"] == upcoming.attributes["parent"])
    #expect(saved.attributes["opaque"] == "child")
    #expect(saved.tags == ["new", "personal"])
    #expect(saved.annotations.contains { $0.text == "personal note" })
    #expect(saved.annotations.contains { $0.text == "New series note" })
    #expect(try await manager.task(id: parent).attributes["mask"] == template.attributes["mask"])
    #expect(try await manager.task(id: past) == overdue)
    #expect(try await manager.task(id: completed) == history)
    await #expect(throws: (any Error).self) { try await manager.applySeriesMetadata(preview) }
}

@Test func seriesMetadataRejectsReservedFieldsInvalidValuesAndStaleMembershipWithoutWriting() async throws {
    let parent = UUID(), child = UUID()
    let template = TaskRecord(id: parent, attributes: ["status": "recurring", "description": "Series", "mask": "-", "due": "200", "recur": "weekly"])
    let occurrence = TaskRecord(id: child, attributes: ["status": "pending", "parent": parent.uuidString, "imask": "0", "due": "200"])
    let replica = OccurrenceReplica(records: [template, occurrence])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    for patch: TaskAttributePatch in [["due": "500"], ["mask": "--"], ["recur": "monthly"], ["parent": UUID().uuidString], ["priority": "invalid"], ["description": "  "], ["tag_BAD": ""], ["opaque": "changed"]] {
        await #expect(throws: (any Error).self) { try await manager.previewSeriesMetadata(id: parent, changes: patch) }
    }
    let preview = try await manager.previewSeriesMetadata(id: parent, changes: ["description": "Revised"])
    _ = try await replica.updateAtomically([TaskAtomicUpdate(id: child, expected: occurrence.attributes, changes: ["due": "300"])])
    let count = await replica.batches
    await #expect(throws: (any Error).self) { try await manager.applySeriesMetadata(preview) }
    #expect(await replica.batches == count)
    #expect(try await manager.task(id: parent) == template)
}
