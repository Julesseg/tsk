#if os(iOS)
import Foundation
import OSLog
import TskCore
import UIKit
import UserNotifications

@available(iOS 15, *)
public actor TaskNotificationScheduler: TaskPostCommitEffect {
    public static let shared = TaskNotificationScheduler()
    private let logger = Logger(subsystem: "com.julesseguin.tsk", category: "TaskNotifications")
    private var pendingManager: TaskManager?
    private var worker: Task<Void, Never>?
    private var requestingAuthorization = false

    public nonisolated static func owns(_ identifier: String) -> Bool { TaskNotificationRequests.owns(identifier) }

    public func apply(to manager: TaskManager, origin: TaskChangeOrigin) async {
        let work = enqueue(manager)
        if let work, await UIApplication.shared.applicationState == .background { await work.value }
    }

    public func refresh(from manager: TaskManager) {
        _ = enqueue(manager)
    }

    private func enqueue(_ manager: TaskManager) -> Task<Void, Never>? {
        #if DEBUG && targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["TSK_TEST_REPLICA_NAME"] == nil else { return nil }
        #endif
        pendingManager = manager
        if let worker { return worker }
        let work = Task { await drain() }
        worker = work
        return work
    }

    private func drain() async {
        while let manager = pendingManager {
            pendingManager = nil
            do { try await reconcile(from: manager) }
            catch { logger.error("Could not refresh task notifications: \(error.localizedDescription)") }
        }
        worker = nil
    }

    private func reconcile(from manager: TaskManager) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard !requestingAuthorization, await UIApplication.shared.applicationState == .active,
                  try await !manager.upcomingNotifications().isEmpty else { return }
            requestAuthorization(from: center, manager: manager)
        case .authorized, .provisional, .ephemeral:
            let pending = await center.pendingNotificationRequests()
            let notifications = try await manager.upcomingNotifications()
            let changes = TaskNotificationRequests(notifications: notifications, pending: pending)
            if !changes.removals.isEmpty { center.removePendingNotificationRequests(withIdentifiers: changes.removals) }
            for request in changes.additions {
                guard let trigger = request.trigger as? UNCalendarNotificationTrigger, trigger.nextTriggerDate() != nil else { continue }
                do { try await center.add(request) }
                catch { logger.error("Could not register a task notification: \(error.localizedDescription)") }
            }
        case .denied:
            let owned = await center.pendingNotificationRequests().map(\.identifier).filter(Self.owns)
            if !owned.isEmpty { center.removePendingNotificationRequests(withIdentifiers: owned) }
        @unknown default:
            break
        }
    }

    private func requestAuthorization(from center: UNUserNotificationCenter, manager: TaskManager) {
        requestingAuthorization = true
        Task {
            defer { requestingAuthorization = false }
            do {
                if try await center.requestAuthorization(options: [.alert]) { refresh(from: manager) }
            } catch { logger.error("Could not request notification permission: \(error.localizedDescription)") }
        }
    }
}
#endif
