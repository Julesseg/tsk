#if canImport(UserNotifications)
@preconcurrency import UserNotifications
import Foundation
import TskCore

public final class UNTaskNotificationCenter: TaskNotificationCenter, @unchecked Sendable {
    public static let payloadKey = "tsk.task-alert.payload"
    private let center: UNUserNotificationCenter
    public init(center: UNUserNotificationCenter = .current()) { self.center = center }

    public func authorization() async throws -> TaskNotificationAuthorization {
        let settings = await withCheckedContinuation { continuation in center.getNotificationSettings { continuation.resume(returning: $0) } }
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unavailable
        }
    }

    public func requestAuthorization() async throws -> TaskNotificationAuthorization {
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: granted) }
            }
        }
        return try await authorization()
    }

    public func pending() async throws -> [PendingTaskNotification] {
        let requests = await withCheckedContinuation { continuation in center.getPendingNotificationRequests { continuation.resume(returning: $0) } }
        return requests.map { request in
            let payload = (request.content.userInfo[Self.payloadKey] as? Data).flatMap { try? JSONDecoder().decode(TaskNotificationRequest.self, from: $0) }
            return PendingTaskNotification(identifier: request.identifier, request: payload, nextTriggerDate: (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
        }
    }

    public func add(_ request: TaskNotificationRequest) async throws {
        guard try await authorization().permitsAlerts else { throw TaskManagementError.storage("Notifications are not permitted. Saved tasks remain available.") }
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.message
        content.sound = .default
        content.userInfo = [Self.payloadKey: try JSONEncoder().encode(request), "taskID": request.taskID.uuidString]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        guard trigger.nextTriggerDate() == request.fireDate else { throw TaskManagementError.storage("The system could not register the requested alert date.") }
        try await addNative(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
    }

    public func remove(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers.filter { $0.hasPrefix(TaskNotificationRequest.identifierPrefix) })
    }

    public func deliveredIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in center.getDeliveredNotifications { continuation.resume(returning: $0.map(\.request.identifier)) } }
    }

    private func addNative(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            center.add(request) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
#endif
