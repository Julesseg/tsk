import Foundation
import Testing
@testable import TskCore

@Test func todayIncludesCarriedPlannedAndDueTasksAtLocalDayBoundary() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let replica = TestReplica()
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1791972000) }, calendar: calendar)
    let fixtures: [(String, [String: String])] = [
        ("Carried forward", ["scheduled": "1791842400"]),
        ("Planned today at last second", ["scheduled": "1792015199"]),
        ("Tomorrow begins", ["scheduled": "1792015200"]),
        ("Due at local midnight", ["due": "1791928800"]),
        ("Overdue", ["due": "1791842400"]),
        ("Unscheduled", [:]),
        ("Started alone", ["start": "1791842400"]),
        ("Waiting and blocked", ["scheduled": "1791842400", "wait": "1792101600", "dep_00000000-0000-0000-0000-000000000001": ""]),
        ("Malformed", ["due": "not a timestamp"])
    ]
    for (name, attributes) in fixtures {
        _ = try await manager.create(TaskDraft(description: name, attributes: attributes))
    }
    _ = try await replica.create(id: UUID(), attributes: ["description": "Template", "status": "recurring", "due": "1791842400"])
    _ = try await replica.create(id: UUID(), attributes: ["description": "Completed", "status": "completed", "scheduled": "1791842400"])
    let names = Set(try await manager.tasks(query: .today).map(\.description))
    #expect(names == ["Carried forward", "Planned today at last second", "Due at local midnight", "Overdue", "Waiting and blocked"])
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
    let tomorrow = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1806271200) }, calendar: calendar)
    #expect(try await tomorrow.tasks(query: .today).contains(where: { $0.id == carried.id }))
    let rescheduled = try await tomorrow.update(id: carried.id, changes: ["scheduled": "1806444000"])
    #expect(rescheduled.id == carried.id)
    #expect(rescheduled.attributes["start"] == "1806148800")
    #expect(rescheduled.attributes["opaque"] == "retain")
    #expect(!((try await tomorrow.tasks(query: .today)).contains { $0.id == carried.id }))
    _ = try await tomorrow.complete(id: todayLate.id)
    #expect(!((try await tomorrow.tasks(query: .today)).contains { $0.id == todayLate.id }))
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
