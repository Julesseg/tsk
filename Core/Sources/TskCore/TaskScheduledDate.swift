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
    static let deadlineAttribute = "tsk_deadline_precision"

    static func read(from attributes: TaskAttributes, field: TaskDateField = .scheduled, calendar: Calendar, inferDeadlinePrecision: Bool = false) -> Self? {
        guard let date = planningDate(attributes[field.attribute]) else { return nil }
        let seconds = String(Int(date.timeIntervalSince1970))
        let hint = attributes[field.precisionAttribute]
        if hint == "v1:\(seconds):timed" { return Self(date: date, hasTime: true) }
        if hint == "v1:\(seconds):untimed" { return Self(date: date, hasTime: false) }
        if field == .deadline, !inferDeadlinePrecision { return Self(date: date, hasTime: true) }
        let clock = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Self(date: date, hasTime: clock.hour != 0 || clock.minute != 0 || clock.second != 0)
    }
}

public extension TaskRecord {
    func scheduled(calendar: Calendar = .autoupdatingCurrent) -> TaskScheduledDate? {
        TaskScheduledDate.read(from: attributes, calendar: calendar)
    }

    func dateIntent(for field: TaskDateField, calendar: Calendar = .autoupdatingCurrent) -> TaskScheduledDate? {
        TaskScheduledDate.read(from: attributes, field: field, calendar: calendar)
    }
}

public extension TaskDraft {
    func scheduled(calendar: Calendar = .autoupdatingCurrent) -> TaskScheduledDate? {
        TaskScheduledDate.read(from: attributes, calendar: calendar)
    }

    func dateIntent(for field: TaskDateField, calendar: Calendar = .autoupdatingCurrent) -> TaskScheduledDate? {
        TaskScheduledDate.read(from: attributes, field: field, calendar: calendar)
    }

    mutating func setScheduled(_ value: TaskScheduledDate?) {
        setDateIntent(value, for: .scheduled)
    }

    mutating func setDateIntent(_ value: TaskScheduledDate?, for field: TaskDateField) {
        if let value {
            let seconds = String(Int(value.date.timeIntervalSince1970))
            attributes[field.attribute] = seconds
            attributes[field.precisionAttribute] = "v1:\(seconds):\(value.hasTime ? "timed" : "untimed")"
        } else {
            attributes[field.attribute] = nil
            attributes[field.precisionAttribute] = nil
        }
    }
}
