import Foundation
import Testing
import TskCore

@Test func bulkScheduledDateChangesOnlyTheChosenFieldAndDeduplicatesMixedTasks() async throws {
    let first = TaskRecord(id: UUID(), attributes: ["description": "First", "status": "pending", "scheduled": "200", "due": "400", "wait": "50", "opaque": "e\u{301}"])
    let second = TaskRecord(id: UUID(), attributes: ["description": "Second", "status": "pending", "due": "600", "project": "work"])
    let replica = OccurrenceReplica(records: [first, second])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    let saved = try await manager.changeDate(ids: [first.id, second.id, first.id], field: .scheduled, change: .set(Date(timeIntervalSince1970: 300)))
    #expect(saved.count == 2)
    for original in [first, second] {
        var expected = original
        expected.attributes["scheduled"] = "300"
        expected.attributes["modified"] = "100"
        #expect(try await manager.task(id: original.id) == expected)
    }
    #expect(await replica.batches == 1)
}

@Test func bulkDeadlineRemovalIsExplicitAndLeavesScheduledAndUnknownFieldsAlone() async throws {
    let first = TaskRecord(id: UUID(), attributes: ["status": "pending", "due": "200", "scheduled": "150", "opaque": "keep"])
    let second = TaskRecord(id: UUID(), attributes: ["status": "pending", "scheduled": "300"])
    let replica = OccurrenceReplica(records: [first, second])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    _ = try await manager.changeDate(ids: [first.id, second.id], field: .deadline, change: .remove)
    #expect(try await manager.task(id: first.id).attributes == ["status": "pending", "scheduled": "150", "opaque": "keep", "modified": "100"])
    #expect(try await manager.task(id: second.id) == second)
}

@Test func bulkDayShortcutsPreserveEachTasksTimeAndReconcileViewMembership() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let first = TaskRecord(id: UUID(), attributes: ["status": "pending", "scheduled": "1792231200", "due": "1792238400"])
    let second = TaskRecord(id: UUID(), attributes: ["status": "pending"])
    let manager = TaskManager(replica: OccurrenceReplica(records: [first, second]), now: { Date(timeIntervalSince1970: 1792144800) }, calendar: calendar)
    #expect(try await manager.tasks(query: .today).isEmpty)
    _ = try await manager.changeDate(ids: [first.id, second.id], field: .scheduled, change: .day(Date(timeIntervalSince1970: 1792144800)))
    #expect(try await manager.task(id: first.id).attributes["scheduled"] == "1792144800")
    #expect(try await manager.task(id: second.id).attributes["scheduled"] == "1792108800")
    #expect(try await manager.tasks(query: .today).count == 2)
    let upcoming = try await manager.upcomingDays().flatMap(\.entries)
    #expect(upcoming.count == 1)
    #expect(upcoming.first?.task.id == first.id)
    _ = try await manager.changeDate(ids: [first.id], field: .deadline, change: .remove)
    #expect(try await manager.upcomingDays().isEmpty)
}

@Test func bulkDateEditsPreserveOccurrenceBookkeepingAndRejectTheWholeInvalidSelection() async throws {
    let parent = TaskRecord(id: UUID(), attributes: ["status": "recurring", "mask": "-W-", "opaque": "series"])
    let first = TaskRecord(id: UUID(), attributes: ["status": "pending", "due": "500", "parent": parent.id.uuidString, "imask": "0.0"])
    let second = TaskRecord(id: UUID(), attributes: ["status": "pending", "due": "600", "wait": "200", "parent": parent.id.uuidString, "imask": "1"])
    let plain = TaskRecord(id: UUID(), attributes: ["status": "pending", "due": "700"])
    let replica = OccurrenceReplica(records: [parent, first, second, plain])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    _ = try await manager.changeDate(ids: [first.id, second.id, plain.id], field: .deadline, change: .set(Date(timeIntervalSince1970: 800)))
    #expect(try await manager.task(id: parent.id) == parent)
    #expect(try await manager.task(id: first.id).attributes["imask"] == "0.0")
    #expect(try await manager.task(id: second.id).attributes["wait"] == "200")
    let original = try await manager.tasks()
    for ids in [[plain.id, first.id], [plain.id, parent.id], [plain.id, UUID()]] {
        await #expect(throws: (any Error).self) { try await manager.changeDate(ids: ids, field: .deadline, change: .remove) }
        #expect(try await manager.tasks() == original)
    }
    _ = try await manager.changeDate(ids: [first.id, second.id], field: .scheduled, change: .remove)
    #expect(try await manager.task(id: parent.id) == parent)
    #expect(await replica.batches == 1)
}

@Test func bulkDateEditsRejectMalformedOccurrencesAndInvalidDatesBeforeWriting() async throws {
    let plain = TaskRecord(id: UUID(), attributes: ["status": "pending"])
    let parent = TaskRecord(id: UUID(), attributes: ["status": "recurring", "mask": "?"])
    let child = TaskRecord(id: UUID(), attributes: ["status": "pending", "parent": parent.id.uuidString, "imask": "0"])
    let original = [plain, parent, child]
    let replica = OccurrenceReplica(records: original)
    let manager = TaskManager(replica: replica)
    await #expect(throws: (any Error).self) { try await manager.changeDate(ids: [plain.id, child.id], field: .scheduled, change: .remove) }
    await #expect(throws: (any Error).self) { try await manager.changeDate(ids: [plain.id], field: .scheduled, change: .set(Date(timeIntervalSince1970: .infinity))) }
    #expect(await replica.records == original)
    #expect(await replica.batches == 0)
}

@Test func bulkDateEditsNeverFallBackToSequentialStorage() async throws {
    let replica = TestReplica()
    let first = try await replica.create(id: UUID(), attributes: ["status": "pending", "scheduled": "200"])
    let second = try await replica.create(id: UUID(), attributes: ["status": "pending"])
    let manager = TaskManager(replica: replica)
    await #expect(throws: (any Error).self) { try await manager.changeDate(ids: [first.id, second.id], field: .scheduled, change: .remove) }
    #expect(try await manager.task(id: first.id) == first)
    #expect(try await manager.task(id: second.id) == second)
}

@Test func selectionCommitCombinesBothDatesAndCompletionInOneTransaction() async throws {
    let parent = TaskRecord(id: UUID(), attributes: ["status": "recurring", "mask": "-W", "opaque": "series"])
    let first = TaskRecord(id: UUID(), attributes: ["status": "pending", "scheduled": "200", "due": "400", "parent": parent.id.uuidString, "imask": "0.0", "start": "20"])
    let second = TaskRecord(id: UUID(), attributes: ["status": "pending", "due": "500", "wait": "300", "parent": parent.id.uuidString, "imask": "1", "opaque": "keep"])
    let replica = OccurrenceReplica(records: [parent, first, second])
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 100) })
    let changes = TaskSelectionChanges(scheduled: .remove, deadline: .set(Date(timeIntervalSince1970: 800)), complete: true)
    #expect(await replica.batches == 0)
    let saved = try await manager.applySelection(ids: [first.id, second.id, first.id], changes: changes)
    #expect(saved.count == 2)
    #expect(saved.allSatisfy { $0.status == "completed" && $0.attributes["due"] == "800" && $0.attributes["scheduled"] == nil && $0.attributes["end"] == "100" && $0.attributes["start"] == nil })
    #expect(try await manager.task(id: parent.id).attributes["mask"] == "++")
    #expect(try await manager.task(id: second.id).attributes["opaque"] == "keep")
    #expect(try await manager.task(id: second.id).attributes["wait"] == "300")
    #expect(await replica.batches == 1)
}

@Test func invalidSelectionChangeRejectsDatesAndCompletionTogether() async throws {
    let parent = TaskRecord(id: UUID(), attributes: ["status": "recurring", "mask": "-"])
    let child = TaskRecord(id: UUID(), attributes: ["status": "pending", "due": "400", "parent": parent.id.uuidString, "imask": "0"])
    let plain = TaskRecord(id: UUID(), attributes: ["status": "pending", "scheduled": "200"])
    let original = [parent, child, plain]
    let replica = OccurrenceReplica(records: original)
    let manager = TaskManager(replica: replica)
    for change in [TaskSelectionChanges(scheduled: .remove, deadline: .remove, complete: true),
                   TaskSelectionChanges(scheduled: .set(Date(timeIntervalSince1970: .infinity)), complete: true)] {
        await #expect(throws: (any Error).self) { try await manager.applySelection(ids: [plain.id, child.id], changes: change) }
        #expect(await replica.records == original)
        #expect(await replica.batches == 0)
    }
}

@Test func unchangedSelectionValuesDoNotTintOrWrite() async throws {
    let task = TaskRecord(id: UUID(), attributes: ["status": "pending", "scheduled": "200", "opaque": "keep"])
    let replica = OccurrenceReplica(records: [task])
    let manager = TaskManager(replica: replica)
    let changes = TaskSelectionChanges(scheduled: .set(Date(timeIntervalSince1970: 200)), deadline: .remove)
    #expect(try !changes.modifies(.scheduled, tasks: [task]))
    #expect(try !changes.modifies(.deadline, tasks: [task]))
    #expect(try TaskSelectionChanges(scheduled: .remove).modifies(.scheduled, tasks: [task]))
    #expect(try await manager.applySelection(ids: [task.id], changes: changes) == [task])
    #expect(await replica.batches == 0)
    #expect(try await manager.applySelection(ids: [task.id], changes: TaskSelectionChanges()) == [task])
    #expect(await replica.batches == 0)
}

@Test func pendingDayPreviewPreservesTheDayAndExistingClockBeforeAnExplicitTimeEdit() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let tomorrow = Date(timeIntervalSince1970: 1792231200)
    let change = TaskDateChange.day(tomorrow)
    let preview = try #require(try change.resolvedDate(replacing: "1792144800", calendar: calendar))
    #expect(calendar.isDate(preview, inSameDayAs: tomorrow))
    #expect(calendar.component(.hour, from: preview) == 10)
    let edited = try #require(calendar.date(bySettingHour: 15, minute: 30, second: 0, of: preview))
    #expect(try TaskDateChange.set(edited).resolvedDate(replacing: nil, calendar: calendar) == edited)
    #expect(try TaskDateChange.remove.resolvedDate(replacing: "1792144800", calendar: calendar) == nil)
}
