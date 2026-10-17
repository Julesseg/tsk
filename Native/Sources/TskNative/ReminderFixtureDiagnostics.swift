#if DEBUG && canImport(EventKit) && targetEnvironment(simulator)
import Foundation
import TskCore

@available(iOS 17.0, macOS 14.0, *)
enum ReminderFixtureDiagnostics {
    static func components(_ value: DateComponents?) -> [String: Any] {
        guard let value else { return ["present": false] }
        var result: [String: Any] = ["present": true, "description": String(describing: value), "timezone": value.timeZone?.identifier as Any? ?? NSNull(), "isLeapMonth": value.isLeapMonth as Any? ?? NSNull()]
        let fields: [(String, Calendar.Component)] = [("era", .era), ("year", .year), ("month", .month), ("day", .day), ("hour", .hour), ("minute", .minute), ("second", .second), ("nanosecond", .nanosecond), ("quarter", .quarter), ("weekday", .weekday), ("weekdayOrdinal", .weekdayOrdinal), ("weekOfMonth", .weekOfMonth), ("weekOfYear", .weekOfYear), ("yearForWeekOfYear", .yearForWeekOfYear)]
        for (name, component) in fields { result[name] = value.value(for: component) as Any? ?? NSNull() }
        if let calendar = value.calendar {
            result["calendar"] = ["identifier": String(describing: calendar.identifier), "locale": calendar.locale?.identifier as Any? ?? NSNull(), "timezone": calendar.timeZone.identifier, "firstWeekday": calendar.firstWeekday, "minimumDaysInFirstWeek": calendar.minimumDaysInFirstWeek, "description": String(describing: calendar)]
        } else { result["calendar"] = NSNull() }
        return result
    }
}
#endif
