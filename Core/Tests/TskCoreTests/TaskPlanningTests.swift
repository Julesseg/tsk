import Foundation
import Testing
@testable import TskCore

@Test func dayPagesUseOnePlannerDateAndContinuousCarryoverOrder() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let replica = TestReplica()
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1791972000) }, calendar: calendar)
    let fixtures: [(String, TaskAttributes)] = [
        ("Older deadline fallback", ["due": "1791763200"]),
        ("Carried untimed", ["scheduled": "1791842400"]),
        ("Carried timed", ["scheduled": "1791885600"]),
        ("Today untimed first", ["scheduled": "1791928800", "entry": "2"]),
        ("Today untimed second", ["scheduled": "1791990000", "entry": "1"]),
        ("Explicit midnight", ["scheduled": "1791928800"]),
        ("Deadline fallback", ["due": "1791972000"]),
        ("Today last second", ["scheduled": "1792015199"]),
        ("Tomorrow overrides overdue Deadline", ["scheduled": "1792015200", "due": "1791842400"]),
        ("Waiting carryover", ["scheduled": "1792015199", "wait": "1792101600", "dep_00000000-0000-0000-0000-000000000001": "x"]),
        ("Unscheduled", [:]),
        ("Started alone", ["start": "1791842400"]),
        ("Malformed", ["due": "not a timestamp"])
    ]
    for (index, fixture) in fixtures.enumerated() {
        var draft = TaskDraft(description: fixture.0, attributes: fixture.1)
        if fixture.0 == "Explicit midnight" {
            draft.setScheduled(TaskScheduledDate(date: Date(timeIntervalSince1970: 1791928800), hasTime: true))
        } else if fixture.0 == "Today untimed second" {
            draft.setScheduled(TaskScheduledDate(date: Date(timeIntervalSince1970: 1791990000), hasTime: false))
        }
        var attributes = draft.attributes
        attributes["description"] = draft.description
        attributes["status"] = "pending"
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
        _ = try await replica.create(id: id, attributes: attributes)
    }
    _ = try await replica.create(id: UUID(), attributes: ["description": "Template", "status": "recurring", "due": "1791842400"])
    _ = try await replica.create(id: UUID(), attributes: ["description": "Completed", "status": "completed", "scheduled": "1791842400"])
    let today = try await manager.dayPage(on: Date(timeIntervalSince1970: 1791972000))
    #expect(today.map(\.description) == ["Older deadline fallback", "Carried untimed", "Carried timed", "Today untimed first", "Today untimed second", "Explicit midnight", "Deadline fallback", "Today last second", "Waiting carryover"])
    #expect(try await manager.tasks(query: .today).map(\.id) == today.map(\.id))
    #expect(try await manager.dayPage(on: Date(timeIntervalSince1970: 1791885600)).isEmpty)
    #expect(try await manager.dayPage(on: Date(timeIntervalSince1970: 1792015200)).map(\.description) == ["Tomorrow overrides overdue Deadline"])
    let waiting = try #require(today.last)
    #expect(try await manager.availability(id: waiting.id).reasons.count == 1)
    #expect(try await manager.task(id: today[1].id).plannedDate == Date(timeIntervalSince1970: 1791842400))
}

@Test func todayCarriesForwardOverDSTAndUsesCalendarDayRatherThan24Hours() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let replica = TestReplica()
    let midnight = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1806188400) }, calendar: calendar)
    let carried = try await midnight.create(TaskDraft(description: "Before DST", attributes: ["scheduled": "1806148800", "start": "1806148800", "opaque": "retain"]))
    let todayLate = try await midnight.create(TaskDraft(description: "DST day late", attributes: ["due": "1806271199"]))
    _ = try await midnight.create(TaskDraft(description: "Tomorrow", attributes: ["due": "1806271200"]))
    #expect(Set(try await midnight.tasks(query: .today).map(\.id)) == [carried.id, todayLate.id])
    #expect(try await midnight.dayPage(on: Date(timeIntervalSince1970: 1806271199)).map(\.id) == [carried.id, todayLate.id])
    #expect(try await midnight.dayPage(on: Date(timeIntervalSince1970: 1806188399)).isEmpty)
    let tomorrow = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1806271200) }, calendar: calendar)
    #expect(try await tomorrow.tasks(query: .today).contains(where: { $0.id == carried.id }))
    let rescheduled = try await tomorrow.update(id: carried.id, changes: ["scheduled": "1806444000"])
    #expect(rescheduled.id == carried.id)
    #expect(rescheduled.attributes["start"] == "1806148800")
    #expect(rescheduled.attributes["opaque"] == "retain")
    #expect(!((try await tomorrow.tasks(query: .today)).contains { $0.id == carried.id }))
    let completed = try await tomorrow.complete(id: todayLate.id)
    #expect(try await tomorrow.tasks(query: .today).contains(completed))
    #expect(!((try await tomorrow.tasks(query: .unfinished)).contains { $0.id == todayLate.id }))
}

@Test func plannedDateAndDeadlineCanBeChangedAndClearedIndependently() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { Date(timeIntervalSince1970: 1791972000) })
    let task = try await manager.create(TaskDraft(description: "Independent dates", attributes: ["scheduled": "1791928800", "due": "1792101600", "start": "1791928800", "opaque": "retain"]))
    let planned = try await manager.update(id: task.id, changes: ["scheduled": "1792015200"])
    #expect(planned.attributes["due"] == "1792101600")
    #expect(planned.attributes["start"] == "1791928800")
    let deadline = try await manager.update(id: task.id, changes: ["due": "1792188000"])
    #expect(deadline.attributes["scheduled"] == "1792015200")
    let cleared = try await manager.update(id: task.id, changes: ["scheduled": nil])
    #expect(cleared.attributes["scheduled"] == nil)
    #expect(cleared.attributes["due"] == "1792188000")
    #expect(cleared.id == task.id)
    #expect(cleared.attributes["opaque"] == "retain")
}

@Test func scheduledPrecisionSurvivesEditingAndExternalChangesWithoutRewritingLegacyDates() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let manager = TaskManager(replica: TestReplica(), calendar: calendar)
    let original = try await manager.create(TaskDraft(description: "Plan", attributes: ["scheduled": "1806188400", "due": "1806271199", "opaque": "retain"]))
    #expect(original.scheduled(calendar: calendar)?.hasTime == false)
    var row = TaskRowDraft(task: original)
    row.taskDraft.setScheduled(TaskScheduledDate(date: original.plannedDate!, hasTime: true))
    let timed = try await manager.updateRow(row)
    #expect(timed.scheduled(calendar: calendar)?.hasTime == true)
    #expect(timed.plannedDate == original.plannedDate)
    row = TaskRowDraft(task: timed)
    row.plan(.tomorrow, now: Date(timeIntervalSince1970: 1806235200), calendar: calendar)
    let moved = try await manager.updateRow(row)
    #expect(moved.plannedDate == Date(timeIntervalSince1970: 1806271200))
    #expect(moved.scheduled(calendar: calendar)?.hasTime == true)
    row = TaskRowDraft(task: moved)
    row.taskDraft.setScheduled(TaskScheduledDate(date: moved.plannedDate!, hasTime: false))
    let untimed = try await manager.updateRow(row)
    #expect(untimed.scheduled(calendar: calendar)?.hasTime == false)
    let external = try await manager.update(id: untimed.id, changes: ["scheduled": "1806326100"])
    #expect(external.scheduled(calendar: calendar)?.hasTime == true)
    #expect(external.attributes["scheduled"] == "1806326100")
    let midnight = try await manager.update(id: external.id, changes: ["scheduled": "1806357600"])
    #expect(midnight.scheduled(calendar: calendar)?.hasTime == false)
    #expect(midnight.attributes["scheduled"] == "1806357600")
    #expect(midnight.attributes["due"] == "1806271199")
    #expect(midnight.attributes["opaque"] == "retain")
    #expect(try TaskRowDraft(task: midnight).changes().isEmpty)
}
