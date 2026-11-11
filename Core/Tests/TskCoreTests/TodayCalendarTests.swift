import Foundation
import Testing
@testable import TskCore

func calendarInstant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

@Test func todayCalendarUsesLocalDSTDayAndClipsSpanningEventsWithoutWritingTasks() async throws {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let now = calendarInstant("2026-03-08T16:00:00Z")
    let manager = TaskManager(replica: TestReplica(), now: { now }, calendar: calendar)
    let task = try await manager.create(TaskDraft(description: "Keep Today task", attributes: ["scheduled": "1772946000", "opaque": "unchanged"]))
    let source = CalendarTestSource(events: [
        calendarEvent("overnight", start: "2026-03-08T04:00:00Z", end: "2026-03-08T07:00:00Z"),
        calendarEvent("all-day", start: "2026-03-07T05:00:00Z", end: "2026-03-10T04:00:00Z", allDay: true),
        calendarEvent("ending-boundary", start: "2026-03-07T10:00:00Z", end: "2026-03-08T05:00:00Z"),
        calendarEvent("tomorrow", start: "2026-03-09T04:00:00Z", end: "2026-03-09T05:00:00Z"),
        calendarEvent("point", start: "2026-03-08T05:00:00Z", end: "2026-03-08T05:00:00Z")
    ])
    let today = await manager.todayCalendar(from: source)
    let day = try #require(today.day)
    #expect(day.start == calendarInstant("2026-03-08T05:00:00Z"))
    #expect(day.end == calendarInstant("2026-03-09T04:00:00Z"))
    #expect(day.duration == 82800)
    #expect(today.events.map(\.event.title) == ["all-day", "point", "overnight"])
    let spanning = try #require(today.events.first)
    #expect(spanning.continuesBefore && spanning.continuesAfter)
    #expect(spanning.visibleStart == day.start && spanning.visibleEnd == day.end)
    let overnight = try #require(today.events.last)
    #expect(overnight.event.start == calendarInstant("2026-03-08T04:00:00Z"))
    #expect(overnight.visibleStart == day.start && overnight.continuesBefore && !overnight.continuesAfter)
    #expect(await source.requestedWindows == [day])
    #expect(try await manager.task(id: task.id) == task)
    #expect(try await manager.tasks(query: .today) == [task])
}

func calendarEvent(_ title: String, start: String, end: String, allDay: Bool = false, canceled: Bool = false, identity: String? = nil) -> CalendarEventSnapshot {
    CalendarEventSnapshot(calendarID: "local", eventID: identity ?? title, title: title, calendarTitle: "Work", start: calendarInstant(start), end: calendarInstant(end), isAllDay: allDay, isCanceled: canceled)
}

actor CalendarTestSource: CalendarEventSource {
    var access: CalendarReadAuthorization
    let values: [CalendarEventSnapshot]
    var requestedWindows: [DateInterval] = []
    var availableCalendars: [CalendarSnapshot] = []
    var calendarReads = 0
    var permissionRequests = 0
    var revokes = false
    var fails = false
    func revokeOnRead() { revokes = true }
    func failReads(_ value: Bool) { fails = value }
    init(access: CalendarReadAuthorization = .fullAccess, events: [CalendarEventSnapshot] = []) { self.access = access; values = events }
    func authorization() -> CalendarReadAuthorization { access }
    func requestReadAccess() { permissionRequests += 1; access = .fullAccess }
    func setCalendars(_ values: [CalendarSnapshot]) { availableCalendars = values }
    func calendars() -> [CalendarSnapshot] { calendarReads += 1; return availableCalendars }
    func events(in window: DateInterval) throws -> [CalendarEventSnapshot] { requestedWindows.append(window); if revokes { access = .denied }; if fails { throw CocoaError(.fileReadUnknown) }; return values }
}

@Test func todayCalendarRequiresExplicitPermissionAndClearsEventsAfterRevocation() async throws {
    let manager = TaskManager(replica: TestReplica(), now: { calendarInstant("2026-11-01T16:00:00Z") })
    let source = CalendarTestSource(access: .notDetermined, events: [calendarEvent("meeting", start: "2026-11-01T15:00:00Z", end: "2026-11-01T16:00:00Z")])
    #expect(await manager.todayCalendar(from: source).authorization == .notDetermined)
    #expect(await source.requestedWindows.isEmpty)
    #expect(await source.permissionRequests == 0)
    #expect(await manager.todayCalendar(from: source, requestingAccess: true).events.count == 1)
    #expect(await source.permissionRequests == 1)
    await source.revokeOnRead()
    let revoked = await manager.todayCalendar(from: source)
    #expect(revoked.authorization == .denied && revoked.events.isEmpty && revoked.readError == nil)
}

@Test func todayCalendarReadFailureDoesNotAffectTaskActionsAndCanRecover() async throws {
    let manager = TaskManager(replica: TestReplica())
    let task = try await manager.create(TaskDraft(description: "Task remains usable"))
    let source = CalendarTestSource()
    await source.failReads(true)
    let failed = await manager.todayCalendar(from: source)
    #expect(failed.authorization == .fullAccess && failed.events.isEmpty && failed.readError != nil)
    _ = try await manager.complete(id: task.id)
    #expect(try await manager.task(id: task.id).status == "completed")
    await source.failReads(false)
    #expect(await manager.todayCalendar(from: source).readError == nil)
}

@Test func todayCalendarFallDSTAndOccurrenceIdentityRemainIndependentOfTasks() async throws {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let manager = TaskManager(replica: TestReplica(), now: { calendarInstant("2026-11-01T16:00:00Z") }, calendar: calendar)
    let first = calendarEvent("first", start: "2026-11-01T05:30:00Z", end: "2026-11-01T05:45:00Z", identity: "series")
    let second = calendarEvent("second", start: "2026-11-01T06:30:00Z", end: "2026-11-01T06:45:00Z", identity: "series")
    let source = CalendarTestSource(events: [second, first, first, calendarEvent("canceled", start: "2026-11-01T08:00:00Z", end: "2026-11-01T09:00:00Z", canceled: true), calendarEvent("invalid", start: "2026-11-01T09:00:00Z", end: "2026-11-01T08:00:00Z")])
    let today = await manager.todayCalendar(from: source)
    #expect(today.day?.duration == 90000)
    #expect(today.events.map(\.event.title) == ["first", "second"])
    #expect(Set(today.events.map(\.id)).count == 2)
    #expect(today.omittedEntryCount == 2)
    #expect(try await manager.tasks().isEmpty)
}

@Test func calendarVisibilityFiltersByIdentityAndPreservesTheCalendarCatalog() async throws {
    let now = calendarInstant("2026-11-01T16:00:00Z")
    let manager = TaskManager(replica: TestReplica(), now: { now })
    let source = CalendarTestSource(events: [
        CalendarEventSnapshot(calendarID: "work", eventID: "meeting", title: "Meeting", calendarTitle: "Calendar", start: now, end: now.addingTimeInterval(3600)),
        CalendarEventSnapshot(calendarID: "personal", eventID: "birthday", title: "Birthday", calendarTitle: "Calendar", start: now, end: now.addingTimeInterval(3600), isAllDay: true)
    ])
    await source.setCalendars([
        CalendarSnapshot(calendarID: "work", title: "Calendar", sourceTitle: "Work account"),
        CalendarSnapshot(calendarID: "personal", title: "Calendar", sourceTitle: "Personal account"),
        CalendarSnapshot(calendarID: "empty", title: "Empty", sourceTitle: "Local")
    ])
    let snapshot = await manager.todayCalendar(from: source)
    #expect(snapshot.calendars.map(\.calendarID) == ["personal", "work", "empty"])
    var visibility = CalendarVisibility()
    #expect(snapshot.showing(visibility).events.count == 2)
    visibility.setVisible(false, calendarID: "work")
    let filtered = snapshot.showing(visibility)
    #expect(filtered.events.map(\.event.title) == ["Birthday"])
    #expect(filtered.calendars == snapshot.calendars)
    visibility.setVisible(false, calendarID: "personal")
    #expect(snapshot.showing(visibility).events.isEmpty)
    #expect(visibility.isVisible("new-calendar"))
    visibility.setVisible(true, calendarID: "work")
    #expect(snapshot.showing(visibility).events.map(\.event.title) == ["Meeting"])
    #expect(snapshot.events.count == 2)
    #expect(try await manager.tasks().isEmpty)
    let encoded = try JSONEncoder().encode(visibility)
    #expect(try JSONDecoder().decode(CalendarVisibility.self, from: encoded) == visibility)
}

@Test func calendarCatalogRequiresAccessAndClearsOnRevocation() async throws {
    let manager = TaskManager(replica: TestReplica())
    let source = CalendarTestSource(access: .notDetermined)
    await source.setCalendars([CalendarSnapshot(calendarID: "local", title: "Local", sourceTitle: "On My iPhone")])
    #expect(await manager.todayCalendar(from: source).calendars.isEmpty)
    #expect(await source.calendarReads == 0)
    #expect(await manager.todayCalendar(from: source, requestingAccess: true).calendars.count == 1)
    await source.revokeOnRead()
    #expect(await manager.todayCalendar(from: source).calendars.isEmpty)
}

@Test func calendarVisibilityPreservesByteDistinctCalendarIdentities() throws {
    let composed = "caf\u{E9}"
    let decomposed = "cafe\u{301}"
    var visibility = CalendarVisibility()
    visibility.setVisible(false, calendarID: composed)
    let restored = try JSONDecoder().decode(CalendarVisibility.self, from: JSONEncoder().encode(visibility))
    #expect(!restored.isVisible(composed))
    #expect(restored.isVisible(decomposed))
}
