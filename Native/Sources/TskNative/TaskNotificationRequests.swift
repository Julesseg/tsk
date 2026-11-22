#if canImport(UserNotifications)
import Foundation
import TskCore
import UserNotifications

@available(iOS 15, macOS 12, *)
struct TaskNotificationRequests {
    private static let prefix = "tsk.timed-task."

    let removals: [String]
    let additions: [UNNotificationRequest]

    init(notifications: [TaskNotification], pending: [UNNotificationRequest]) {
        let desired = notifications.map(Self.request)
        let identifiers = Set(desired.map(\.identifier))
        let owned = pending.filter { Self.owns($0.identifier) }
        let existing = Dictionary(uniqueKeysWithValues: owned.map { ($0.identifier, $0) })
        removals = owned.map(\.identifier).filter { !identifiers.contains($0) }
        additions = desired.filter { request in
            guard let prior = existing[request.identifier] else { return true }
            return !Self.matches(prior, request)
        }
    }

    static func owns(_ identifier: String) -> Bool { identifier.hasPrefix(prefix) }

    private static func request(for notification: TaskNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.interruptionLevel = .timeSensitive

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notification.fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = prefix + notification.taskID.uuidString.lowercased() + "." + String(notification.fireDate.timeIntervalSince1970)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private static func matches(_ prior: UNNotificationRequest, _ desired: UNNotificationRequest) -> Bool {
        guard let trigger = prior.trigger as? UNCalendarNotificationTrigger,
              !trigger.repeats, trigger.dateComponents == (desired.trigger as? UNCalendarNotificationTrigger)?.dateComponents else { return false }
        let content = prior.content
        return content.title.utf8.elementsEqual(desired.content.title.utf8)
            && content.body.isEmpty && content.subtitle.isEmpty && content.sound == nil && content.badge == nil
            && content.interruptionLevel == .timeSensitive
    }
}
#endif
