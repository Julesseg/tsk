import Foundation
import Testing
import TskCore

@Test func notificationsDeriveDistinctAndCombinedEventsWithoutChangingStoredTaskDates() async throws {
    let replica = TestReplica()
    let manager = TaskManager(replica: replica, now: { Date(timeIntervalSince1970: 1792100000) })
    let combined = try await manager.create(TaskDraft(description: "Review", attributes: ["scheduled": "1792108800", "due": "1792141200", "opaque": "keep"]))
    let separate = try await manager.create(TaskDraft(description: "Distinct", attributes: ["scheduled": "1792141200", "due": "1792144800"]))
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let plan = try await manager.notificationPlan(calendar: calendar)
    let review = try #require(plan.future.first { $0.taskID == combined.id })
    #expect(review.kind == .combined)
    #expect(review.fireDate == Date(timeIntervalSince1970: 1792141200))
    #expect(review.events.map(\.storedSeconds) == [1792108800, 1792141200])
    #expect(plan.future.filter { $0.taskID == separate.id }.count == 2)
    #expect(try await manager.task(id: combined.id) == combined)
    let disabled = try await manager.notificationPlan(preferences: TaskNotificationPreferences(midnightReplacement: false), calendar: calendar)
    #expect(disabled.future.filter { $0.taskID == combined.id }.map(\.fireDate) == [Date(timeIntervalSince1970: 1792108800), Date(timeIntervalSince1970: 1792141200)])
    #expect(try await manager.task(id: combined.id) == combined)
}

@Test func midnightFallbackUsesCurrentDeviceZoneAndExplicitDSTResolutionWhileOtherTimesRemainAbsolute() throws {
    let parser = ISO8601DateFormatter()
    let id = UUID()
    func record(_ text: String, status: String = "pending") throws -> TaskRecord {
        TaskRecord(id: id, attributes: ["status": status, "due": String(Int(try #require(parser.date(from: text)).timeIntervalSince1970))])
    }
    var paris = Calendar(identifier: .gregorian); paris.timeZone = TimeZone(identifier: "Europe/Paris")!
    let now = try #require(parser.date(from: "2026-01-01T00:00:00Z"))
    for (original, expected) in [("2026-03-28T23:00:00Z", "2026-03-29T01:00:00Z"), ("2026-10-24T22:00:00Z", "2026-10-25T00:30:00Z")] {
        let task = try record(original)
        let plan = try TaskManager.notificationPlan(tasks: [task], preferences: TaskNotificationPreferences(hour: 2, minute: 30), calendar: paris, at: now)
        #expect(plan.future.first?.fireDate == parser.date(from: expected))
        #expect(plan.future.first?.events.first?.storedSeconds == Int64(task.attributes["due"]!))
    }
    let absolute = try record("2026-03-29T10:15:00Z")
    #expect(try TaskManager.notificationPlan(tasks: [absolute], calendar: paris, at: now).future.first?.fireDate == parser.date(from: "2026-03-29T10:15:00Z"))
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
    let midnight = try record("2026-03-29T00:00:00Z")
    #expect(try TaskManager.notificationPlan(tasks: [midnight], calendar: utc, at: now).future.first?.fireDate == parser.date(from: "2026-03-29T09:00:00Z"))
    #expect(try TaskManager.notificationPlan(tasks: [midnight], calendar: paris, at: now).future.first?.fireDate == parser.date(from: "2026-03-29T00:00:00Z"))
    let excluded = [try record("2026-03-29T10:00:00Z", status: "completed"), try record("2026-03-29T10:00:00Z", status: "deleted"), TaskRecord(id: UUID(), attributes: ["status": "recurring", "due": "1792144800", "recur": "daily"])]
    #expect(try TaskManager.notificationPlan(tasks: excluded, calendar: paris, at: now).future.isEmpty)
}
