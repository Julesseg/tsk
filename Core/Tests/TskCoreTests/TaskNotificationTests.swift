import Foundation
import Testing
@testable import TskCore

struct TaskNotificationTests {
    @Test func onlyFutureTimedDatesOnActionableTasksProduceNotifications() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = Date(timeIntervalSince1970: 1_893_456_000)
        let morning = midnight.addingTimeInterval(3_600)
        let later = morning.addingTimeInterval(3_600)
        let now = midnight.addingTimeInterval(-1)

        func task(_ scheduled: TaskScheduledDate?, _ deadline: TaskScheduledDate?, status: String = "pending") -> TaskRecord {
            var draft = TaskDraft(attributes: ["description": "Review draft", "status": status])
            draft.setScheduled(scheduled)
            draft.setDateIntent(deadline, for: .deadline)
            return TaskRecord(id: UUID(), attributes: draft.attributes)
        }

        let untimed = TaskScheduledDate(date: midnight, hasTime: false)
        let timedMidnight = TaskScheduledDate(date: midnight, hasTime: true)
        let timedMorning = TaskScheduledDate(date: morning, hasTime: true)
        let scheduledOnly = task(timedMidnight, untimed)
        let deadlineOnly = task(untimed, timedMorning)
        let both = task(timedMorning, .init(date: later, hasTime: true))
        let coincident = task(timedMorning, timedMorning)
        let untimedOnly = task(untimed, untimed)
        let past = task(.init(date: now, hasTime: true), .init(date: now.addingTimeInterval(-1), hasTime: true))
        let completed = task(timedMorning, timedMorning, status: "completed")
        let deleted = task(timedMorning, timedMorning, status: "deleted")
        let template = task(timedMorning, timedMorning, status: "recurring")

        let notifications = TaskNotification.upcoming(for: [both, coincident, untimedOnly, past, completed, deleted, template, deadlineOnly, scheduledOnly], at: now, calendar: calendar)

        #expect(notifications.map(\.fireDate) == [midnight, morning, morning, morning, later])
        #expect(notifications.filter { $0.taskID == scheduledOnly.id }.map(\.fireDate) == [midnight])
        #expect(notifications.filter { $0.taskID == deadlineOnly.id }.map(\.fireDate) == [morning])
        #expect(notifications.filter { $0.taskID == both.id }.map(\.fireDate) == [morning, later])
        #expect(notifications.filter { $0.taskID == coincident.id }.map(\.fireDate) == [morning])
        #expect(notifications.allSatisfy { $0.title == "Review draft" })
    }

    @Test func usesExistingDatePrecisionForLegacyTasks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = Date(timeIntervalSince1970: 1_893_456_000)
        let morning = midnight.addingTimeInterval(3_600)
        let task = TaskRecord(id: UUID(), attributes: [
            "status": "pending", "scheduled": "1893456000", "due": "1893456000",
        ])
        let edited = TaskRecord(id: UUID(), attributes: [
            "status": "pending", "scheduled": "1893459600", "due": "1893456000",
            "tsk_deadline_precision": "v1:1893456000:untimed",
        ])

        #expect(TaskNotification.upcoming(for: [task, edited], at: midnight.addingTimeInterval(-1), calendar: calendar).map(\.fireDate) == [midnight, morning])
    }
}
