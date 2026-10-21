import Foundation
import Testing
import TskCore

@MainActor @Test func calendarHoursPersistAcrossPreferenceInstancesAndRecoverInvalidData() throws {
    let name = "CalendarOverviewProof.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let first = CalendarOverviewPreferences(defaults: defaults)
    #expect(first.hours == CalendarDisplayHours())
    first.hours = CalendarDisplayHours(startHour: 6, endHour: 24)
    #expect(CalendarOverviewPreferences(defaults: defaults).hours == CalendarDisplayHours(startHour: 6, endHour: 24))
    defaults.set(Data("{\"startHour\":23,\"endHour\":1}".utf8), forKey: "calendar-overview-hours")
    #expect(CalendarOverviewPreferences(defaults: defaults).hours == CalendarDisplayHours())
    defaults.set(Data("not json".utf8), forKey: "calendar-overview-hours")
    #expect(CalendarOverviewPreferences(defaults: defaults).hours == CalendarDisplayHours())
}
