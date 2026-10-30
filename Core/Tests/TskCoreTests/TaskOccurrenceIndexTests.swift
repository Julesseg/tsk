import Foundation
import Testing
@testable import TskCore

@Test(arguments: ["0", "0.000000", "1", "1.000000", "001.00", "9007199254740993.000000", "\(Int.max).000000"])
func wholeNumberOccurrencePositionsRemainActionable(raw: String) throws {
    let task = TaskRecord(id: UUID(), attributes: ["status": "pending", "parent": UUID().uuidString, "imask": raw, "recur": "monthly", "due": "200"])
    let expected = try #require(Int(raw.split(separator: ".")[0]))
    #expect(task.canEdit && task.canComplete && task.canChangeActivity)
    #expect(task.recurrenceInspection?.index == expected)
    #expect(task.recurrenceInspection?.issues.isEmpty == true)
    #expect(task.attributes["imask"] == raw)
}

@Test(arguments: ["", "-1", "-1.000000", "+1", "1.5", "1.000001", "1.0000000000000000001", "NaN", "inf", "1e0", " 1", "1 ", ".0", "1.", "1.0.0", "١", "9223372036854775808.000000"])
func invalidOccurrencePositionsStayUnavailable(raw: String) async throws {
    let parent = TaskRecord(id: UUID(), attributes: ["status": "recurring", "mask": "--"])
    let task = TaskRecord(id: UUID(), attributes: ["status": "pending", "parent": parent.id.uuidString, "imask": raw, "recur": "monthly", "due": "200"])
    #expect(!task.canEdit && !task.canComplete && !task.canChangeActivity)
    #expect(task.recurrenceInspection?.index == nil)
    let records = [parent, task]
    let replica = OccurrenceReplica(records: records)
    let manager = TaskManager(replica: replica)
    await #expect(throws: (any Error).self) { try await manager.complete(id: task.id) }
    #expect(await replica.records == records)
    #expect(await replica.batches == 0)
}

@Test func decimalOccurrenceSupportsEditingActivityAndAtomicCompletionWithoutRewritingItsIndex() async throws {
    let parent = UUID(), child = UUID(), historyID = UUID()
    let template = TaskRecord(id: parent, attributes: ["status": "recurring", "description": "Series", "recur": "monthly", "due": "200", "mask": "+-"])
    let history = TaskRecord(id: historyID, attributes: ["status": "completed", "parent": parent.uuidString, "imask": "0", "due": "50"])
    let occurrence = TaskRecord(id: child, attributes: ["status": "pending", "description": "Occurrence", "parent": parent.uuidString, "imask": "1.000000", "recur": "monthly", "due": "200", "opaque": "preserve"])
    let replica = OccurrenceReplica(records: [template, history, occurrence])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    _ = try await manager.update(id: child, changes: ["description": "Edited occurrence", "wait": "150"])
    #expect(try await manager.task(id: parent).attributes["mask"] == "+W")
    _ = try await manager.start(id: child)
    #expect(try await manager.task(id: child).isActive)
    _ = try await manager.stop(id: child)
    #expect(try await !manager.task(id: child).isActive)
    let completed = try await manager.complete(id: child)
    #expect(completed.status == "completed")
    #expect(completed.attributes["imask"] == "1.000000")
    #expect(completed.attributes["opaque"] == "preserve")
    #expect(try await manager.task(id: parent).attributes["mask"] == "++")
    #expect(try await manager.task(id: historyID) == history)
    #expect(try await manager.complete(id: child) == completed)
    #expect(await replica.batches == 4)
}

@Test func equivalentIntegerAndDecimalSiblingPositionsCannotBeCompletedOrEditedAsASeries() async throws {
    let parent = UUID()
    let template = TaskRecord(id: parent, attributes: ["status": "recurring", "mask": "--", "description": "Series", "due": "200", "recur": "daily"])
    let first = TaskRecord(id: UUID(), attributes: ["status": "pending", "parent": parent.uuidString, "imask": "1", "due": "200"])
    let duplicate = TaskRecord(id: UUID(), attributes: ["status": "pending", "parent": parent.uuidString, "imask": "1.000000", "due": "200"])
    let records = [template, first, duplicate]
    let replica = OccurrenceReplica(records: records)
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    for task in [first, duplicate] {
        await #expect(throws: (any Error).self) { try await manager.complete(id: task.id) }
    }
    await #expect(throws: TaskSeriesMetadataError.self) { try await manager.previewSeriesMetadata(id: parent, changes: ["description": "Changed"]) }
    #expect(await replica.records == records)
    #expect(await replica.batches == 0)
}

@Test func decimalOccurrenceSupportsSeriesMetadataAndCadenceChanges() async throws {
    let parent = UUID(), child = UUID(), historyID = UUID()
    let template = TaskRecord(id: parent, attributes: ["status": "recurring", "description": "Series", "recur": "daily", "due": "100", "mask": "+-"])
    let history = TaskRecord(id: historyID, attributes: ["status": "completed", "parent": parent.uuidString, "imask": "0.000000", "due": "100"])
    let occurrence = TaskRecord(id: child, attributes: ["status": "pending", "description": "Occurrence", "parent": parent.uuidString, "imask": "1.000000", "due": "200"])
    let replica = OccurrenceReplica(records: [template, history, occurrence])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    let metadata = try await manager.previewSeriesMetadata(id: parent, changes: ["description": "Revised"])
    #expect(metadata.affected.map(\.id) == [child])
    #expect(await replica.batches == 0)
    _ = try await manager.applySeriesMetadata(metadata)
    #expect(try await manager.task(id: child).description == "Revised")
    #expect(try await manager.task(id: child).attributes["imask"] == "1.000000")
    let transition = try await manager.previewSeriesTransition(id: parent, draft: TaskSeriesTransitionDraft(effectiveDate: Date(timeIntervalSince1970: 100), firstDue: Date(timeIntervalSince1970: 1000), recurrence: "weekly", generatorTimeZone: "UTC"))
    #expect(transition.affected.map(\.id) == [child])
    #expect(await replica.batches == 1)
    let successor = try await manager.applySeriesTransition(transition)
    #expect(try await manager.task(id: parent).attributes["mask"] == "+X")
    #expect(successor.attributes["mask"] == "-")
    #expect(try await manager.task(id: child).attributes["parent"] == successor.id.uuidString.lowercased())
    #expect(try await manager.task(id: child).attributes["imask"] == "0")
    #expect(try await manager.task(id: historyID) == history)
}
