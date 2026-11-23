import Foundation

public struct TaskNotification: Sendable {
    public let taskID: UUID
    public let title: String
    public let fireDate: Date

    public static func upcoming(for tasks: [TaskRecord], at now: Date, calendar: Calendar = .autoupdatingCurrent) -> [Self] {
        tasks.filter(\.canComplete).flatMap { task in
            let dates = TaskDateField.allCases.compactMap { field -> Date? in
                guard let intent = task.dateIntent(for: field, calendar: calendar),
                      intent.hasTime, intent.date > now else { return nil }
                return intent.date
            }
            return Set(dates).map { Self(taskID: task.id, title: task.description, fireDate: $0) }
        }.sorted { ($0.fireDate, $0.taskID.uuidString) < ($1.fireDate, $1.taskID.uuidString) }
    }
}

public extension TaskManager {
    func upcomingNotifications() async throws -> [TaskNotification] {
        let records = try await replica.tasks()
        return TaskNotification.upcoming(for: records, at: now(), calendar: calendar)
    }
}
