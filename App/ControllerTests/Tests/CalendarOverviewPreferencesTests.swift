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

@MainActor @Test func calendarVisibilityPersistsAndRecoversInvalidData() throws {
    let name = "CalendarVisibilityProof.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let first = CalendarOverviewPreferences(defaults: defaults)
    #expect(first.visibility.isVisible("work"))
    first.visibility.setVisible(false, calendarID: "work")
    let reopened = CalendarOverviewPreferences(defaults: defaults)
    #expect(!reopened.visibility.isVisible("work"))
    #expect(reopened.visibility.isVisible("personal"))
    reopened.visibility.setVisible(true, calendarID: "work")
    #expect(CalendarOverviewPreferences(defaults: defaults).visibility.isVisible("work"))
    defaults.set(Data("not json".utf8), forKey: "calendar-visibility")
    #expect(CalendarOverviewPreferences(defaults: defaults).visibility == CalendarVisibility())
}
