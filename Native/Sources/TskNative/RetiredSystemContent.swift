#if os(iOS)
import CoreSpotlight
import Foundation
import UserNotifications

@MainActor
public enum RetiredSystemContent {
    public static func remove() async throws {
        let key = "retired-system-content-2026-11-17"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let notifications = UNUserNotificationCenter.current()
        notifications.removeAllPendingNotificationRequests()
        notifications.removeAllDeliveredNotifications()
        try await CSSearchableIndex.default().deleteAllSearchableItems()
        UserDefaults.standard.set(true, forKey: key)
    }
}
#endif
