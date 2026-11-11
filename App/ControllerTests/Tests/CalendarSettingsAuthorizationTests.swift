import Foundation
import Testing
import TskCore
import TskNative

extension CalendarControllerProof {
    @Test func calendarSettingsRefreshesChangedAuthorizationOutsideTodayWithoutPrompting() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = CalendarSettingsSource()
        let controller = TodayCalendarController(manager: TaskChampionSession.makeManager(directory: directory), source: source)
        #expect(!controller.isDisplayingToday)
        await controller.refreshAuthorization()
        #expect(controller.snapshot?.authorization == .fullAccess)
        await source.setAccess(.denied)
        await controller.refreshAuthorization()
        #expect(controller.snapshot?.authorization == .denied)
        await source.setAccess(.fullAccess)
        await controller.refreshAuthorization()
        #expect(controller.snapshot?.authorization == .fullAccess)
        #expect(await source.requests == 0)
        #expect(await source.reads == 2)
    }

    @Test func calendarSettingsPreservesReadFailureUntilExplicitRetryWhenAuthorizationIsUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = CalendarSettingsSource()
        let controller = TodayCalendarController(manager: TaskChampionSession.makeManager(directory: directory), source: source)
        await source.setFailure(true)
        await controller.refresh()
        #expect(controller.snapshot?.readError != nil)
        await source.setFailure(false)
        await controller.refreshAuthorization()
        await controller.refreshSettings()
        #expect(controller.snapshot?.readError != nil)
        #expect(await source.reads == 1)
        await controller.refresh()
        #expect(controller.snapshot?.readError == nil)
        #expect(await source.reads == 2)
        #expect(await source.requests == 0)
    }

    @Test func visibilityUpdatesCachedEventsImmediatelyAndSurvivesRefreshAndRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "CalendarVisibilityControllerProof.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: name) }
        let source = CalendarSettingsSource()
        let preferences = CalendarOverviewPreferences(defaults: defaults)
        let controller = TodayCalendarController(manager: TaskChampionSession.makeManager(directory: directory), source: source, preferences: preferences)
        let work = CalendarSnapshot(calendarID: "work", title: "Work", sourceTitle: "iCloud")
        await source.setCalendars([work])
        await controller.refresh()
        #expect(controller.snapshot?.events.count == 1)
        preferences.visibility.setVisible(false, calendarID: "work")
        #expect(controller.snapshot?.events.isEmpty == true)
        #expect(controller.snapshot?.calendars == [work])
        #expect(await source.reads == 1)
        await controller.refresh()
        #expect(controller.snapshot?.events.isEmpty == true)
        let reopened = TodayCalendarController(manager: controller.manager, source: source, preferences: CalendarOverviewPreferences(defaults: defaults))
        await reopened.refresh()
        #expect(reopened.snapshot?.events.isEmpty == true)
        reopened.preferences.visibility.setVisible(true, calendarID: "work")
        #expect(reopened.snapshot?.events.count == 1)
        await source.setCalendars([CalendarSnapshot(calendarID: "empty", title: "Empty", sourceTitle: "Local")])
        await reopened.refreshSettings()
        #expect(reopened.snapshot?.calendars.map(\.calendarID) == ["empty"])
        await source.setAccess(.denied)
        await reopened.refreshAuthorization()
        #expect(reopened.snapshot?.calendars.isEmpty == true)
    }

}

private actor CalendarSettingsSource: CalendarEventSource {
    var access = CalendarReadAuthorization.fullAccess
    var failing = false
    var availableCalendars: [CalendarSnapshot] = []
    var requests = 0
    var reads = 0
    func authorization() -> CalendarReadAuthorization { access }
    func requestReadAccess() { requests += 1 }
    func setAccess(_ value: CalendarReadAuthorization) { access = value }
    func setFailure(_ value: Bool) { failing = value }
    func setCalendars(_ values: [CalendarSnapshot]) { availableCalendars = values }
    func calendars() -> [CalendarSnapshot] { availableCalendars }
    func events(in window: DateInterval) throws -> [CalendarEventSnapshot] {
        reads += 1
        if failing { throw CocoaError(.fileReadUnknown) }
        return [CalendarEventSnapshot(calendarID: "work", eventID: "meeting", title: "Meeting", calendarTitle: "Work", start: window.start, end: window.end)]
    }
}
