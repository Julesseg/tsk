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
        return TaskScheduledDate.read(from: attributes, field: .deadline, calendar: calendar, inferDeadlinePrecision: true)
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
        set {
            let raw = newValue.map { String(Int($0.timeIntervalSince1970)) }
            if raw != attributes["due"] { attributes[TaskScheduledDate.deadlineAttribute] = nil }
            attributes["due"] = raw
        }
    }
}

public extension TaskManager {
    func rollOverUntimedScheduledTasks() async throws {
        let today = calendar.startOfDay(for: now())
        let candidates = try await replica.tasks()
        guard candidates.contains(where: { needsScheduledRollover($0, today: today) }) else { return }

        let lease = try await beginMutation()
        defer { endMutation(lease) }
        let currentDay = calendar.startOfDay(for: now())
        let records = try await replica.tasks()
        let incoming = records.filter { needsScheduledRollover($0, today: currentDay) }
            .sorted { TaskPlannerOrder.precedes($0, $1, on: currentDay, calendar: calendar) }
            .map { task in
                var rolled = task
                var draft = TaskDraft(attributes: task.attributes)
                draft.setScheduled(.init(date: currentDay, hasTime: false))
                rolled.attributes = draft.attributes
                return rolled
            }
        guard !incoming.isEmpty else { return }
        _ = try await saveOrder(appendingIncoming(incoming, to: records), context: .day(currentDay), records: records)
    }

    private func needsScheduledRollover(_ task: TaskRecord, today: Date) -> Bool {
        guard task.canComplete, let intent = task.scheduled(calendar: calendar) else { return false }
        return !intent.hasTime && intent.date < today
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
    private static func position(_ task: TaskRecord, on day: Date, calendar: Calendar) -> (Int, Date, Int) {
        if let scheduled = task.scheduled(calendar: calendar) {
            if scheduled.date < day { return (0, scheduled.date, scheduled.hasTime ? 1 : 0) }
            if scheduled.hasTime { return (3, scheduled.date, 0) }
            return (2, calendar.startOfDay(for: scheduled.date), 0)
        }
        if let deadline = task.deadline { return (1, deadline, 0) }
        return (2, day, 1)
    }

    static func groupPrecedes(_ lhs: TaskRecord, _ rhs: TaskRecord, on day: Date, calendar: Calendar) -> Bool {
        position(lhs, on: day, calendar: calendar) < position(rhs, on: day, calendar: calendar)
    }

    static func precedes(_ lhs: TaskRecord, _ rhs: TaskRecord, on day: Date, calendar: Calendar) -> Bool {
        let left = position(lhs, on: day, calendar: calendar)
        let right = position(rhs, on: day, calendar: calendar)
        if left != right { return left < right }
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
