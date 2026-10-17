import Foundation
import Testing
@testable import TskCore

@Test func upcomingGroupsBothDateRolesByLocalDayWithOnePersistentIdentity() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1791972000) }, calendar: calendar)
    let first = try await manager.create(TaskDraft(description: "One task two days", attributes: ["scheduled": "1792015200", "due": "1792101600", "opaque": "keep"]))
    let sameDay = try await manager.create(TaskDraft(description: "Two roles same day", attributes: ["scheduled": "1792015200", "due": "1792015200"]))
    _ = try await manager.create(TaskDraft(description: "Today", attributes: ["scheduled": "1792015199", "due": "1792015199"]))
    _ = try await manager.create(TaskDraft(description: "Unscheduled"))
    let groups = try await manager.upcomingDays()
    #expect(groups.map(\.day) == [Date(timeIntervalSince1970: 1792015200), Date(timeIntervalSince1970: 1792101600)])
    let appearances = groups.flatMap(\.entries).filter { $0.task.id == first.id }
    #expect(appearances.count == 2)
    #expect(appearances.map(\.role) == [.planned, .deadline])
    #expect(Set(appearances.map(\.id)).count == 2)
    #expect(appearances.allSatisfy { $0.task.attributes["opaque"] == "keep" })
    let sameDayEntries = groups[0].entries.filter { $0.task.id == sameDay.id }
    #expect(sameDayEntries.map(\.role) == [.planned, .deadline])
    #expect(Set(sameDayEntries.map(\.id)).count == 2)
    #expect(Set(try await manager.tasks(query: .upcoming).map(\.id)) == [first.id, sameDay.id])
}

@Test func upcomingUsesLocalDSTDayBoundaryAndOrdersTimeRoleAndIdentity() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let replica = TestReplica()
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1806188400) }, calendar: calendar)
    _ = try await manager.create(TaskDraft(description: "Still today", attributes: ["due": "1806271199"]))
    let planned = try await manager.create(TaskDraft(description: "Zebra planned", attributes: ["scheduled": "1806271200"]))
    let deadline = try await manager.create(TaskDraft(description: "Alpha deadline", attributes: ["due": "1806271200"]))
    let later = try await manager.create(TaskDraft(description: "Later", attributes: ["scheduled": "1806314400"]))
    _ = try await manager.create(TaskDraft(description: "Invalid dates", attributes: ["scheduled": "NaN", "due": "broken"]))
    _ = try await replica.create(id: UUID(), attributes: ["description": "Completed", "status": "completed", "due": "1806271200"])
    _ = try await replica.create(id: UUID(), attributes: ["description": "Template", "status": "recurring", "due": "1806271200"])
    let occurrence = try await replica.create(id: UUID(), attributes: ["description": "Occurrence", "status": "pending", "due": "1806357600", "parent": UUID().uuidString, "wait": "1806530400"])
    let groups = try await manager.upcomingDays()
    #expect(groups.map(\.day) == [Date(timeIntervalSince1970: 1806271200), Date(timeIntervalSince1970: 1806357600)])
    #expect(groups[0].entries.map { $0.task.id } == [planned.id, deadline.id, later.id])
    #expect(groups[1].entries.map { $0.task.id } == [occurrence.id])
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    let otherZone = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1806188400) }, calendar: utc)
    #expect(try await otherZone.upcomingDays().first?.day == Date(timeIntervalSince1970: 1806192000))
}

@Test func upcomingDateEditsRebuildEntriesAndCompletionRemovesEveryAppearance() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1791972000) }, calendar: calendar)
    let task = try await manager.create(TaskDraft(description: "Edit one identity", attributes: ["scheduled": "1792015200", "due": "1792101600", "start": "1791928800", "opaque": "retain"]))
    let originalEntries = try await manager.upcomingDays().flatMap(\.entries)
    _ = try await manager.update(id: task.id, changes: ["scheduled": "1792188000", "description": "Replanned"])
    let edited = try await manager.upcomingDays()
    #expect(edited.map(\.day) == [Date(timeIntervalSince1970: 1792101600), Date(timeIntervalSince1970: 1792188000)])
    #expect(edited.flatMap(\.entries).map(\.role) == [.deadline, .planned])
    #expect(edited.flatMap(\.entries).allSatisfy { $0.task.id == task.id && $0.task.description == "Replanned" })
    #expect(edited.flatMap(\.entries).first?.id == originalEntries.last?.id)
    #expect(edited.flatMap(\.entries).last?.id != originalEntries.first?.id)
    #expect(try await manager.tasks().count == 1)
    _ = try await manager.update(id: task.id, changes: ["due": nil])
    #expect(try await manager.upcomingDays().flatMap(\.entries).map(\.role) == [.planned])
    let stored = try await manager.task(id: task.id)
    #expect(stored.attributes["start"] == "1791928800")
    #expect(stored.attributes["opaque"] == "retain")
    _ = try await manager.complete(id: task.id)
    #expect(try await manager.upcomingDays().isEmpty)
    #expect(try await manager.tasks().count == 1)
    #expect(try await manager.task(id: task.id).status == "completed")
}
