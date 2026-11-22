#if canImport(UserNotifications)
import Foundation
import Testing
import TskCore
@testable import TskNative
import UserNotifications

struct TaskNotificationRequestsTests {
    @Test func registersTitleOnlyTimeSensitiveRequestsAndReconcilesChanges() throws {
        guard #available(iOS 15, macOS 12, *) else { return }
        let date = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.up) + 3_600)
        let later = date.addingTimeInterval(60)
        let id = UUID()
        func notifications(title: String, date: Date) -> [TaskNotification] {
            let task = TaskRecord(id: id, attributes: [
                "description": title, "status": "pending", "due": String(Int(date.timeIntervalSince1970)),
            ])
            return TaskNotification.upcoming(for: [task], at: date.addingTimeInterval(-3_600))
        }

        let original = notifications(title: "Send draft", date: date)
        let initial = TaskNotificationRequests(notifications: original, pending: [])
        let request = try #require(initial.additions.first)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(initial.additions.count == 1)
        #expect(request.content.title == "Send draft")
        #expect(request.content.subtitle.isEmpty)
        #expect(request.content.body.isEmpty)
        #expect(request.content.badge == nil)
        #expect(request.content.sound == nil)
        #expect(request.content.interruptionLevel == .timeSensitive)
        #expect(trigger.nextTriggerDate() == date)
        #expect(!trigger.repeats)

        let other = UNNotificationRequest(identifier: "other-notification", content: request.content, trigger: nil)
        let pending = [request, other]
        let identical = TaskNotificationRequests(notifications: original, pending: pending)
        #expect(identical.additions.isEmpty)
        #expect(identical.removals.isEmpty)

        let renamed = TaskNotificationRequests(notifications: notifications(title: "Send final draft", date: date), pending: pending)
        #expect(renamed.additions.map(\.identifier) == [request.identifier])
        #expect(renamed.additions.map(\.content.title) == ["Send final draft"])
        #expect(renamed.removals.isEmpty)

        let rescheduled = TaskNotificationRequests(notifications: notifications(title: "Send draft", date: later), pending: pending)
        #expect(rescheduled.additions.count == 1)
        #expect(rescheduled.additions.first?.identifier != request.identifier)
        #expect(rescheduled.removals == [request.identifier])

        let removed = TaskNotificationRequests(notifications: [], pending: pending)
        #expect(removed.additions.isEmpty)
        #expect(removed.removals == [request.identifier])
    }
}
#endif
