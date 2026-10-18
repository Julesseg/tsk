import Foundation

public enum ReminderRecurrenceMapping {
    public static let supportedDescription = "Local weekly reminders at 09:00 GMT with identical start and due, Gregorian calendar, interval 1, Monday week start, no selectors or end. Other recurring rules remain in Reminders."

    static func rule(for reminder: ReminderSnapshot) throws -> String? {
        guard let raw = reminder.recurrenceDescription else { return nil }
        let reason = "Recurring reminder left unchanged: only the verified local Gregorian weekly 09:00 GMT rule with equal start/due, interval 1, Monday week start, no selectors or end is supported. Rule: \(raw)"
        guard validationChecks(for: reminder).values.allSatisfy({ $0 }) else { throw TaskManagementError.storage(reason) }
        return "1week"
    }

    public static func validationChecks(for reminder: ReminderSnapshot) -> [String: Bool] {
        let rules = reminder.recurrenceDescription?.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
        let encoded = rules.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
        let start = reminder.start.flatMap(canonicalAnchor)
        let due = reminder.due.flatMap(canonicalAnchor)
        return [
            "localSource": reminder.sourceType == 0,
            "oneRule": rules?.count == 1,
            "supportedRuleSignature": encoded == signature,
            "canonicalStart": start != nil,
            "canonicalDue": due != nil,
            "sameCanonicalAnchor": start != nil && start == due
        ]
    }

    private static func canonicalAnchor(_ components: DateComponents) -> Date? {
        guard var calendar = components.calendar, calendar.identifier == .gregorian,
              components.timeZone?.identifier == "GMT", let year = components.year, let month = components.month, let day = components.day,
              components.hour == 9, components.minute == 0, components.second == 0,
              components.nanosecond == nil || components.nanosecond == 0,
              components.era == nil || components.era == 1, components.isLeapMonth != true else { return nil }
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let primary = DateComponents(calendar: calendar, timeZone: calendar.timeZone, era: 1, year: year, month: month, day: day, hour: 9, minute: 0, second: 0)
        guard let date = calendar.date(from: primary) else { return nil }
        let required: [Calendar.Component] = [.year, .month, .day, .hour, .minute, .second]
        let derived: [Calendar.Component] = [.quarter, .weekday, .weekdayOrdinal, .weekOfMonth, .weekOfYear, .yearForWeekOfYear]
        for component in required + derived {
            if let supplied = components.value(for: component), supplied != calendar.component(component, from: date) { return nil }
        }
        return date
    }

    private static let signature = Data(#"[{"calendar":"gregorian","endCount":0,"endDate":null,"firstDayOfWeek":2,"frequency":1,"interval":1,"monthdays":[],"months":[],"positions":[],"weekdays":[],"yeardays":[],"yearweeks":[]}]"#.utf8)
}
