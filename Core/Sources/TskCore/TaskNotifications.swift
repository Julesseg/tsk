import Foundation

public struct TaskNotificationPreferences: Codable, Equatable, Sendable {
    public var midnightReplacement: Bool
    public var hour: Int
    public var minute: Int
    public init(midnightReplacement: Bool = true, hour: Int = 9, minute: Int = 0) {
        self.midnightReplacement = midnightReplacement; self.hour = hour; self.minute = minute
    }
}

public enum TaskNotificationSource: String, Codable, Hashable, Sendable { case planned, due }
public enum TaskNotificationKind: String, Codable, Sendable { case planned, due, combined }

public struct TaskNotificationEvent: Codable, Hashable, Sendable {
    public let taskID: UUID
    public let source: TaskNotificationSource
    public let storedSeconds: Int64
    public init(taskID: UUID, source: TaskNotificationSource, storedSeconds: Int64) {
        self.taskID = taskID; self.source = source; self.storedSeconds = storedSeconds
    }
}

public struct TaskNotificationRequest: Codable, Equatable, Sendable {
    public static let identifierPrefix = "tsk.task-alert."
    public let taskID: UUID
    public let title: String
    public let kind: TaskNotificationKind
    public let fireDate: Date
    public let events: [TaskNotificationEvent]
    public var identifier: String { Self.identifierPrefix + taskID.uuidString.lowercased() + "." + kind.rawValue }
    public var message: String {
        switch kind { case .planned: "Planned work"; case .due: "Task is due"; case .combined: "Planned and due" }
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.taskID == rhs.taskID && lhs.title.matchesBytes(rhs.title) && lhs.kind == rhs.kind && lhs.fireDate == rhs.fireDate && lhs.events == rhs.events
    }
}

public struct TaskNotificationPlan: Sendable {
    public let future: [TaskNotificationRequest]
    public let past: [TaskNotificationRequest]
    public let invalidTaskIDs: [UUID]
}

public enum TaskNotificationError: Error, LocalizedError, Sendable {
    case invalidPreferences
    case invalidCalendar
    case changedDuringReconciliation
    public var errorDescription: String? {
        switch self {
        case .invalidPreferences: "Choose a valid midnight replacement time."
        case .invalidCalendar: "An alert date could not be calculated in the current device time zone."
        case .changedDuringReconciliation: "Tasks changed while alerts were being updated. Retry to reconcile the latest saved tasks."
        }
    }
}

public extension TaskManager {
    func notificationPlan(preferences: TaskNotificationPreferences = .init(), calendar: Calendar = .autoupdatingCurrent) async throws -> TaskNotificationPlan {
        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let records = try await replica.tasks()
        return try Self.notificationPlan(tasks: records, preferences: preferences, calendar: calendar, at: now())
    }

    static func notificationPlan(tasks: [TaskRecord], preferences: TaskNotificationPreferences = .init(), calendar: Calendar = .autoupdatingCurrent, at instant: Date) throws -> TaskNotificationPlan {
        guard (0...23).contains(preferences.hour), (0...59).contains(preferences.minute) else { throw TaskNotificationError.invalidPreferences }
        var requests: [TaskNotificationRequest] = []
        var invalid = Set<UUID>()
        for task in tasks where task.canComplete {
            var events: [(TaskNotificationEvent, Date)] = []
            for (source, field) in [(TaskNotificationSource.planned, "scheduled"), (.due, "due")] {
                guard let raw = task.attributes[field], !raw.isEmpty else { continue }
                guard let seconds = Int64(raw), seconds >= 0, seconds <= 253402300799 else { invalid.insert(task.id); continue }
                let date = Date(timeIntervalSince1970: Double(seconds))
                let clock = calendar.dateComponents([.hour, .minute, .second], from: date)
                let effective: Date
                if preferences.midnightReplacement, clock.hour == 0, clock.minute == 0, clock.second == 0 {
                    guard let replacement = calendar.date(bySettingHour: preferences.hour, minute: preferences.minute, second: 0, of: date, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) else { throw TaskNotificationError.invalidCalendar }
                    effective = replacement
                } else { effective = date }
                events.append((TaskNotificationEvent(taskID: task.id, source: source, storedSeconds: seconds), effective))
            }
            if events.count == 2, events[0].1 == events[1].1 {
                requests.append(TaskNotificationRequest(taskID: task.id, title: task.description, kind: .combined, fireDate: events[0].1, events: events.map(\.0)))
            } else {
                for (event, date) in events { requests.append(TaskNotificationRequest(taskID: task.id, title: task.description, kind: event.source == .planned ? .planned : .due, fireDate: date, events: [event])) }
            }
        }
        requests.sort { ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier) }
        return TaskNotificationPlan(future: requests.filter { $0.fireDate > instant }, past: requests.filter { $0.fireDate <= instant }, invalidTaskIDs: invalid.sorted { $0.uuidString < $1.uuidString })
    }
}
