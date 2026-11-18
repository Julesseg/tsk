import Foundation

public struct TaskScheduledDate: Equatable, Sendable {
    public var date: Date
    public var hasTime: Bool

    public init(date: Date, hasTime: Bool) {
        self.date = date
        self.hasTime = hasTime
    }
}

extension TaskScheduledDate {
    static let attribute = "tsk_scheduled_precision"

    static func read(from attributes: TaskAttributes, calendar: Calendar) -> Self? {
        guard let date = planningDate(attributes["scheduled"]) else { return nil }
        let seconds = String(Int(date.timeIntervalSince1970))
        let hint = attributes[attribute]
        if hint == "v1:\(seconds):timed" { return Self(date: date, hasTime: true) }
        if hint == "v1:\(seconds):untimed" { return Self(date: date, hasTime: false) }
        let clock = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Self(date: date, hasTime: clock.hour != 0 || clock.minute != 0 || clock.second != 0)
    }
}

public extension TaskRecord {
    func scheduled(calendar: Calendar = .autoupdatingCurrent) -> TaskScheduledDate? {
        TaskScheduledDate.read(from: attributes, calendar: calendar)
    }
}

public extension TaskDraft {
    func scheduled(calendar: Calendar = .autoupdatingCurrent) -> TaskScheduledDate? {
        TaskScheduledDate.read(from: attributes, calendar: calendar)
    }

    mutating func setScheduled(_ value: TaskScheduledDate?) {
        plannedDate = value?.date
        if let value, let seconds = attributes["scheduled"] {
            attributes[TaskScheduledDate.attribute] = "v1:\(seconds):\(value.hasTime ? "timed" : "untimed")"
        } else {
            attributes[TaskScheduledDate.attribute] = nil
        }
    }
}
