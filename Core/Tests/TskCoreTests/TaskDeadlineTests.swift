import Foundation
import Testing
import TskCore

@Test func deadlineOffsetsUseCalendarDaysAcrossMidnightAndDaylightSaving() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let format = ISO8601DateFormatter()
    let now = try #require(format.date(from: "2026-03-08T05:30:00Z"))
    for (raw, expected) in [("2026-03-08T04:59:00Z", -1), ("2026-03-08T05:00:00Z", 0),
                            ("2026-03-09T03:59:00Z", 0), ("2026-03-09T04:00:00Z", 1),
                            ("2026-03-11T04:00:00Z", 3)] {
        let due = try #require(format.date(from: raw))
        let task = TaskRecord(id: UUID(), attributes: ["due": String(Int(due.timeIntervalSince1970)), "scheduled": "0"])
        #expect(task.deadlineDayOffset(relativeTo: now, calendar: calendar) == expected)
    }
    let task = TaskRecord(id: UUID(), attributes: ["due": "invalid", "scheduled": "0"])
    #expect(task.deadlineDayOffset(relativeTo: now, calendar: calendar) == nil)
}
