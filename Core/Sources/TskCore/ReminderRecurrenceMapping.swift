import Foundation

public enum ReminderRecurrenceMapping {
    public static let supportedDescription = "Local weekly reminders at 09:00 GMT with identical start and due, Gregorian calendar, interval 1, Monday week start, no selectors or end. Other recurring rules remain in Reminders."

    static func rule(for reminder: ReminderSnapshot) throws -> String? {
        guard let raw = reminder.recurrenceDescription else { return nil }
        let reason = "Recurring reminder left unchanged: only the verified local Gregorian weekly 09:00 GMT rule with equal start/due, interval 1, Monday week start, no selectors or end is supported. Rule: \(raw)"
        guard reminder.sourceType == 0, let data = raw.data(using: .utf8),
              let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], rules.count == 1,
              let actual = try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]),
              actual == signature,
              let start = reminder.start, let due = reminder.due, start == due,
              start.calendar?.identifier == .gregorian,
              start.timeZone?.identifier == "GMT", start.year != nil, start.month != nil, start.day != nil,
              start.hour == 9, start.minute == 0, start.second == 0,
              start.nanosecond == nil || start.nanosecond == 0,
              start.era == nil || start.era == 1,
              start.quarter == nil, start.weekday == nil, start.weekdayOrdinal == nil,
              start.weekOfMonth == nil, start.weekOfYear == nil, start.yearForWeekOfYear == nil,
              start.isLeapMonth != true else { throw TaskManagementError.storage(reason) }
        return "1week"
    }

    private static let signature = Data(#"[{"calendar":"gregorian","endCount":0,"endDate":null,"firstDayOfWeek":2,"frequency":1,"interval":1,"monthdays":[],"months":[],"positions":[],"weekdays":[],"yeardays":[],"yearweeks":[]}]"#.utf8)
}
