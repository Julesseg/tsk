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
    await #expect(throws: (any Error).self) {
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

@Test func carriedCompletionRetainsOccupiedDayAndManualOrderWithoutChangingDates() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let monday = Date(timeIntervalSince1970: 1791763200)
    let wednesday = Date(timeIntervalSince1970: 1791936000)
    let records = (0..<3).map { _ in TaskRecord(id: UUID(), attributes: ["status": "pending", "description": "Carried", "scheduled": "1791763200", "due": "1792108800", "opaque": "retain"]) }
    let incoming = TaskRecord(id: UUID(), attributes: ["status": "pending", "description": "Incoming work"])
    let replica = OccurrenceReplica(records: records + [incoming])
    let manager = TaskManager(replica: replica, now: { wednesday }, calendar: calendar)
    let before = try await manager.dayPage(on: wednesday)
    var drag = try TaskDragSession(tasks: before, ids: [before[2].id], context: .day(wednesday), calendar: calendar)
    drag.cross(before[0].id)
    _ = try await manager.drop(drag)
    let ordered = try await manager.dayPage(on: wednesday)
    let target = ordered[1]
    let saved = try #require(try await manager.complete(ids: [target.id]).first)
    #expect(try await manager.dayPage(on: wednesday).map(\.id) == ordered.map(\.id))
    #expect(try await manager.dayPage(on: monday).isEmpty)
    #expect(saved.status == "completed")
    #expect(saved.plannedDate == target.plannedDate && saved.deadline == target.deadline)
    #expect(saved.attributes["opaque"] == "retain")
    drag = try TaskDragSession(tasks: try await manager.dayPage(on: wednesday), ids: [ordered[0].id], context: .day(wednesday), calendar: calendar)
    drag.cross(ordered[2].id)
    _ = try await manager.drop(drag)
    #expect(try await manager.dayPage(on: wednesday).map(\.id) == [target.id, ordered[2].id, ordered[0].id])
    _ = try await manager.schedule(ids: [incoming.id], change: .intent(.init(date: monday, hasTime: false)))
    #expect(try await manager.dayPage(on: wednesday).map(\.id) == [target.id, ordered[2].id, ordered[0].id, incoming.id])
    let later = TaskManager(replica: replica, now: { wednesday.addingTimeInterval(86400) }, calendar: calendar)
    #expect(try await later.dayPage(on: wednesday).map(\.id) == [target.id])
    let retained = try await manager.task(id: target.id)
    #expect(try await later.complete(id: target.id) == retained)
    #expect(try await manager.tasks(query: .unfinished).count == 3)
}

@Test func earlyCompletionRemainsOnFuturePlannerDayAndIsNotUnfinishedWork() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let wednesday = Date(timeIntervalSince1970: 1791936000)
    let friday = Date(timeIntervalSince1970: 1792108800)
    let manager = TaskManager(replica: TestReplica(), now: { wednesday }, calendar: calendar)
    let task = try await manager.create(TaskDraft(description: "Finish early", attributes: ["scheduled": "1792108800", "due": "1792281600", "project": "Home", "opaque": "keep"]))
    let saved = try await manager.complete(id: task.id)
    #expect(try await manager.dayPage(on: friday) == [saved])
    #expect(try await manager.dayPage(on: wednesday).isEmpty)
    #expect(saved.plannedDate == task.plannedDate && saved.deadline == task.deadline)
    #expect(saved.attributes["opaque"] == "keep")
    #expect(try await manager.tasks(query: .unfinished, project: .project("Home")).isEmpty)
    #expect(try await manager.tasks(query: .inbox).isEmpty)
    #expect(try await manager.tasks(query: .upcoming).isEmpty)
    let editedHistory = try await manager.update(id: saved.id, changes: ["scheduled": "1792281600"])
    #expect(try await manager.dayPage(on: friday) == [editedHistory])
    #expect(try await manager.dayPage(on: Date(timeIntervalSince1970: 1792281600)).isEmpty)
}

@Test func uncompletingReleasesRetainedPlacementAndPreservesScheduledIntent() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = Date(timeIntervalSince1970: 1792108800)
    let tomorrow = day.addingTimeInterval(86400)
    let manager = TaskManager(replica: TestReplica(), now: { day.addingTimeInterval(3600) }, calendar: calendar)
    var draft = TaskDraft(description: "Reopen on its planned day", attributes: ["due": "1792400000", "opaque": "keep"])
    draft.setScheduled(.init(date: day, hasTime: true))
    let task = try await manager.create(draft)
    let completed = try await manager.complete(id: task.id)
    #expect(completed.attributes[TaskCompletionPlacement.attribute] != nil)
    let edited = try await manager.update(id: task.id, changes: ["scheduled": String(Int(tomorrow.timeIntervalSince1970))])
    #expect(try await manager.dayPage(on: day) == [edited])
    let reopened = try await manager.reopen(id: task.id)
    #expect(reopened.status == "pending")
    #expect(reopened.attributes["end"] == nil)
    #expect(reopened.attributes[TaskCompletionPlacement.attribute] == nil)
    #expect(reopened.deadline == task.deadline)
    #expect(reopened.scheduled(calendar: calendar) == edited.scheduled(calendar: calendar))
    #expect(reopened.attributes["opaque"] == "keep")
    #expect(try await manager.dayPage(on: day).isEmpty)
    #expect(try await manager.dayPage(on: tomorrow) == [reopened])
    #expect(try await manager.reopen(id: task.id) == reopened)
}
