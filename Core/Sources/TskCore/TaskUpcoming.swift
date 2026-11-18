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
            guard let date = task.plannerDate(calendar: calendar)?.date, date >= boundary else { continue }
            let day = calendar.startOfDay(for: date)
            let role: TaskDateRole = task.plannedDate == nil ? .deadline : .planned
            days[day, default: []].append(UpcomingTaskEntry(task: task, role: role, date: date))
        }
        return days.keys.sorted().map { day in
            UpcomingDay(day: day, entries: days[day, default: []].sorted {
                TaskPlannerOrder.precedes($0.task, $1.task, calendar: calendar)
            })
        }
    }
}

public extension TaskRecord {
    func isInUpcoming(at now: Date, calendar: Calendar) -> Bool {
        guard status == "pending", let boundary = calendar.dateInterval(of: .day, for: now)?.end else { return false }
        return plannerDate(calendar: calendar).map { $0.date >= boundary } ?? false
    }
}
