import Foundation

public enum TaskDateRole: String, Hashable, Sendable {
    case planned, deadline
}

public struct UpcomingEntryID: Hashable, Sendable {
    public let taskID: UUID
    public let role: TaskDateRole
    public let date: Date
}

public struct UpcomingTaskEntry: Identifiable, Equatable, Sendable {
    public let task: TaskRecord
    public let role: TaskDateRole
    public let date: Date
    public var id: UpcomingEntryID { UpcomingEntryID(taskID: task.id, role: role, date: date) }
}

public struct UpcomingDay: Identifiable, Equatable, Sendable {
    public let day: Date
    public let entries: [UpcomingTaskEntry]
    public var id: Date { day }

    public static func groups(tasks: [TaskRecord], at now: Date, calendar: Calendar = .autoupdatingCurrent) -> [UpcomingDay] {
        guard let boundary = calendar.dateInterval(of: .day, for: now)?.end else { return [] }
        var days: [Date: [UpcomingTaskEntry]] = [:]
        for task in tasks where task.status == "pending" {
            let dates: [(TaskDateRole, Date?)] = [(.planned, task.plannedDate), (.deadline, task.deadline)]
            for (role, date) in dates {
                guard let date, date >= boundary else { continue }
                let day = calendar.startOfDay(for: date)
                days[day, default: []].append(UpcomingTaskEntry(task: task, role: role, date: date))
            }
        }
        return days.keys.sorted().map { day in
            UpcomingDay(day: day, entries: days[day, default: []].sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                if $0.role != $1.role { return $0.role == .planned }
                if $0.task.description != $1.task.description { return $0.task.description < $1.task.description }
                return $0.task.id.uuidString < $1.task.id.uuidString
            })
        }
    }
}

public extension TaskRecord {
    func isInUpcoming(at now: Date, calendar: Calendar) -> Bool {
        guard status == "pending", let boundary = calendar.dateInterval(of: .day, for: now)?.end else { return false }
        return [plannedDate, deadline].compactMap { $0 }.contains { $0 >= boundary }
    }
}
