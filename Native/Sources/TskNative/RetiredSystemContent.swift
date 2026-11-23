#if os(iOS)
import CoreSpotlight
import Foundation
import UserNotifications

@MainActor
public enum RetiredSystemContent {
    public static func remove() async throws {
        let key = "retired-system-content-2026-11-17"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        if #available(iOS 15, *) {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter(isRetired)
            let delivered = await center.deliveredNotifications().map(\.request.identifier).filter(isRetired)
            if !pending.isEmpty { center.removePendingNotificationRequests(withIdentifiers: pending) }
            if !delivered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: delivered) }
        }
        try await CSSearchableIndex.default().deleteAllSearchableItems()
        UserDefaults.standard.set(true, forKey: key)
    }

    private static func isRetired(_ identifier: String) -> Bool {
        identifier.hasPrefix("tsk.task-alert.") || identifier.hasPrefix("tsk.task-missed.")
    }
}
#endif
