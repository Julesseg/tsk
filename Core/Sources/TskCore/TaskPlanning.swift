import Foundation

public extension TaskRecord {
    var plannedDate: Date? { dateAttribute("scheduled") }
    var deadline: Date? { dateAttribute("due") }
    var waitUntil: Date? { dateAttribute("wait") }
    var startedAt: Date? { dateAttribute("start") }

    func scheduledDayOffset(relativeTo today: Date, calendar: Calendar = .autoupdatingCurrent) -> Int? {
        dayOffset(for: plannedDate, relativeTo: today, calendar: calendar)
    }

    func deadlineDayOffset(relativeTo today: Date, calendar: Calendar = .autoupdatingCurrent) -> Int? {
        dayOffset(for: deadline, relativeTo: today, calendar: calendar)
    }

    private func dayOffset(for date: Date?, relativeTo today: Date, calendar: Calendar) -> Int? {
        guard let date else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: date)).day
    }

    func isInToday(at now: Date, calendar: Calendar) -> Bool {
        isOnDay(now, at: now, calendar: calendar)
    }

    func plannerDate(calendar: Calendar = .autoupdatingCurrent) -> TaskScheduledDate? {
        if let scheduled = scheduled(calendar: calendar) { return scheduled }
        guard let deadline else { return nil }
        let clock = calendar.dateComponents([.hour, .minute, .second], from: deadline)
        return TaskScheduledDate(date: deadline, hasTime: clock.hour != 0 || clock.minute != 0 || clock.second != 0)
    }

    internal func isOnDay(_ day: Date, at now: Date, calendar: Calendar) -> Bool {
        if status == "completed" { return TaskCompletionPlacement.includes(self, day: day, calendar: calendar) }
        guard status == "pending", let date = plannerDate(calendar: calendar)?.date else { return false }
        let today = calendar.startOfDay(for: now)
        let original = calendar.startOfDay(for: date)
        return max(today, original) == calendar.startOfDay(for: day)
    }

    private func dateAttribute(_ name: String) -> Date? {
        planningDate(attributes[name])
    }
}

public extension TaskDraft {
    var waitUntil: Date? {
        get { planningDate(attributes["wait"]) }
        set { attributes["wait"] = newValue.map { String(Int($0.timeIntervalSince1970)) } }
    }

    var plannedDate: Date? {
        get { planningDate(attributes["scheduled"]) }
        set {
            attributes["scheduled"] = newValue.map { String(Int($0.timeIntervalSince1970)) }
            attributes[TaskScheduledDate.attribute] = nil
        }
    }

    mutating func schedule(on day: Date, calendar: Calendar = .autoupdatingCurrent) {
        let intent = scheduled(calendar: calendar)
        let hasMetadata = attributes[TaskScheduledDate.attribute] != nil
        plannedDate = taskDate(on: day, keepingTimeFrom: plannedDate, calendar: calendar)
        if hasMetadata, let date = plannedDate, let intent {
            setScheduled(TaskScheduledDate(date: date, hasTime: intent.hasTime))
        }
    }

    var deadline: Date? {
        get { planningDate(attributes["due"]) }
        set { attributes["due"] = newValue.map { String(Int($0.timeIntervalSince1970)) } }
    }
}

func planningDate(_ raw: String?) -> Date? {
    guard let raw, let seconds = TimeInterval(raw), seconds.isFinite,
          abs(seconds) <= 253402300799 else { return nil }
    return Date(timeIntervalSince1970: seconds)
}

func taskDate(on day: Date, keepingTimeFrom date: Date?, calendar: Calendar) -> Date? {
    let time = date.map { calendar.dateComponents([.hour, .minute, .second], from: $0) }
    return calendar.date(bySettingHour: time?.hour ?? 0, minute: time?.minute ?? 0,
                         second: time?.second ?? 0, of: day)
}

internal enum TaskPlannerOrder {
    static func groupPrecedes(_ lhs: TaskRecord, _ rhs: TaskRecord, calendar: Calendar) -> Bool {
        if let left = lhs.plannerDate(calendar: calendar), let right = rhs.plannerDate(calendar: calendar) {
            let leftDay = calendar.startOfDay(for: left.date)
            let rightDay = calendar.startOfDay(for: right.date)
            if leftDay != rightDay { return leftDay < rightDay }
            if left.hasTime != right.hasTime { return !left.hasTime }
            if left.hasTime, left.date != right.date { return left.date < right.date }
        }
        return false
    }

    static func precedes(_ lhs: TaskRecord, _ rhs: TaskRecord, calendar: Calendar) -> Bool {
        if groupPrecedes(lhs, rhs, calendar: calendar) { return true }
        if groupPrecedes(rhs, lhs, calendar: calendar) { return false }
        if let group = TaskManualOrder.plannerGroup(lhs, calendar: calendar),
           let result = TaskManualOrder.precedes(lhs, rhs, attribute: TaskManualOrder.plannerAttribute, group: group) { return result }
        return entryPrecedes(lhs, rhs)
    }

    static func entryPrecedes(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
        if lhs.attributes["entry"] != rhs.attributes["entry"] {
            return (lhs.attributes["entry"] ?? "") > (rhs.attributes["entry"] ?? "")
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
