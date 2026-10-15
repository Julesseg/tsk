import Foundation

public enum TaskSeriesTransitionError: Error, Equatable, LocalizedError, Sendable {
    case invalidDate
    case invalidTimeZone
    case ambiguousCalendarDate
    case invalidOffset
    case incompleteGeneratorHorizon
    case untilBeforeRetainedOccurrence

    public var errorDescription: String? {
        switch self {
        case .invalidDate: "Choose a first due date on or after the effective date, within the supported calendar range."
        case .invalidTimeZone: "Choose a valid generator time zone and use that same zone on the designated Taskwarrior client."
        case .ambiguousCalendarDate: "A rescheduled occurrence lands in a missing or repeated clock time in the generator time zone. Choose another first due time or time zone."
        case .invalidOffset: "A saved planned or wait offset is invalid or falls outside the supported date range. No tasks were changed."
        case .incompleteGeneratorHorizon: "The old series is not generated through the effective date. Run and synchronize the designated generator first, then preview again."
        case .untilBeforeRetainedOccurrence: "The Until date precedes a retained future occurrence. Extend or clear Until before transitioning."
        }
    }
}

struct TaskRecurrenceSchedule {
    let rule: TaskRecurrenceRule
    let zone: TimeZone
    let calendar: Calendar

    init(rule: String, timeZone: String) throws {
        self.rule = try TaskRecurrenceRule(rule)
        guard let zone = TimeZone(identifier: timeZone) else { throw TaskSeriesTransitionError.invalidTimeZone }
        self.zone = zone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        self.calendar = calendar
    }

    func dates(first: Date, count: Int) throws -> [Date] {
        guard Self.valid(first), rule.supportsFirstDue(first.timeIntervalSince1970) else { throw TaskSeriesTransitionError.invalidDate }
        guard count > 0 else { return [] }
        var dates = [first]
        while dates.count < count { dates.append(try next(dates.last!)) }
        return dates
    }

    func next(_ current: Date) throws -> Date {
        let raw = rule.rawValue
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: current)
        let year = components.year!, month = components.month!, day = components.day!
        var months: Int?
        var midnight = false
        if raw == "monthly" || raw == "P1M" { months = 1 }
        else if let match = TaskwarriorDuration.captures(#"^([0-9]+)m$"#, raw) { months = Int(match[1]) }
        else if let match = TaskwarriorDuration.captures(#"^P([0-9]+)M$"#, raw) { months = Int(match[1]); midnight = true }
        else if raw == "quarterly" { months = 3 }
        else if let match = TaskwarriorDuration.captures(#"^([0-9]+)q$"#, raw), let quantity = Int(match[1]) { months = quantity * 3 }
        else if raw == "semiannual" { months = 6 }
        else if raw == "bimonthly" { months = 2 }
        if let months {
            let absolute = year * 12 + month - 1 + months
            let newYear = absolute / 12, newMonth = absolute % 12 + 1
            return try wallDate(year: newYear, month: newMonth, day: min(day, Self.days(year: newYear, month: newMonth)), hour: midnight ? 0 : components.hour!, minute: midnight ? 0 : components.minute!, second: midnight ? 0 : components.second!)
        }
        if ["yearly", "annual", "P1Y", "biannual", "biyearly", "P2Y"].contains(raw) {
            let years = ["biannual", "biyearly", "P2Y"].contains(raw) ? 2 : 1
            let leapDay = month == 2 && day == 29
            return try wallDate(year: year + years, month: leapDay && years == 2 ? 3 : month, day: leapDay ? (years == 2 ? 1 : 28) : day, hour: components.hour!, minute: components.minute!, second: components.second!)
        }
        let seconds: Int64
        if raw == "weekdays" {
            let weekday = calendar.component(.weekday, from: current)
            seconds = Int64(weekday == 6 ? 3 : weekday == 7 ? 2 : 1) * 86400
        } else { seconds = TaskwarriorDuration(raw, allowRawSeconds: false)!.seconds }
        let next = current.addingTimeInterval(Double(seconds))
        guard Self.valid(next), next > current else { throw TaskSeriesTransitionError.invalidDate }
        return next
    }

    private func wallDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) throws -> Date {
        guard (1970...9999).contains(year) else { throw TaskSeriesTransitionError.invalidDate }
        let wanted = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        guard let date = calendar.date(from: wanted), calendar.dateComponents(fields, from: date) == wanted else { throw TaskSeriesTransitionError.ambiguousCalendarDate }
        let offset = zone.secondsFromGMT(for: date)
        let alternatives = [-15552000.0, -172800, 172800, 15552000].map { zone.secondsFromGMT(for: date.addingTimeInterval($0)) }
        for alternative in Set(alternatives) where alternative != offset {
            let candidate = date.addingTimeInterval(Double(offset - alternative))
            if calendar.dateComponents(fields, from: candidate) == wanted { throw TaskSeriesTransitionError.ambiguousCalendarDate }
        }
        guard Self.valid(date) else { throw TaskSeriesTransitionError.invalidDate }
        return date
    }

    static func valid(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite && date.timeIntervalSince1970 > 0 && date.timeIntervalSince1970 <= 253402300799 }

    private static func days(year: Int, month: Int) -> Int {
        if month == 2 { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28 }
        return [4, 6, 9, 11].contains(month) ? 30 : 31
    }
}
