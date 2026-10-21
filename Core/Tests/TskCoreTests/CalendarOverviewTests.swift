import Foundation
import Testing
@testable import TskCore

@Test func calendarOverviewProjectsConfiguredLocalHoursWithoutDiscardingOtherEvents() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendarInstant("2026-10-16T00:00:00Z")
    let source = CalendarTestSource(events: [
        calendarEvent("All day", start: "2026-10-16T00:00:00Z", end: "2026-10-17T00:00:00Z", allDay: true),
        calendarEvent("Early", start: "2026-10-16T06:00:00Z", end: "2026-10-16T07:00:00Z"),
        calendarEvent("Clipped", start: "2026-10-16T07:00:00Z", end: "2026-10-16T09:00:00Z"),
        calendarEvent("Point", start: "2026-10-16T12:00:00Z", end: "2026-10-16T12:00:00Z"),
        calendarEvent("At end", start: "2026-10-16T18:00:00Z", end: "2026-10-16T18:00:00Z")
    ])
    let snapshot = await TaskManager(replica: TestReplica(), now: { day }, calendar: calendar).todayCalendar(from: source)
    let overview = CalendarOverview(snapshot: snapshot, hours: CalendarDisplayHours())
    #expect(overview.allDay.map(\.event.title) == ["All day"])
    #expect(overview.outsideHours.map(\.event.title) == ["Early", "At end"])
    #expect(overview.items.map(\.value.event.title) == ["Clipped", "Point"])
    #expect(overview.items[0].start == 0 && overview.items[0].end == 0.1)
    #expect(overview.items[1].start == 0.4 && overview.items[1].end == 0.4)
    #expect(snapshot.events.count == 5)
}

@Test func calendarDisplayHoursValidateSavedValuesAndUseLocalDSTBoundaries() throws {
    let invalid = try JSONDecoder().decode(CalendarDisplayHours.self, from: Data("{\"startHour\":20,\"endHour\":8}".utf8))
    #expect(invalid == CalendarDisplayHours())
    let fullDay = CalendarDisplayHours(startHour: 0, endHour: 24)
    #expect(try JSONDecoder().decode(CalendarDisplayHours.self, from: JSONEncoder().encode(fullDay)) == fullDay)
    let zone = TimeZone(identifier: "America/New_York")!
    let spring = DateInterval(start: calendarInstant("2026-03-08T05:00:00Z"), end: calendarInstant("2026-03-09T04:00:00Z"))
    #expect(fullDay.window(on: spring, timeZone: zone) == spring)
    #expect(CalendarDisplayHours().window(on: spring, timeZone: zone)?.start == calendarInstant("2026-03-08T12:00:00Z"))
    let fall = DateInterval(start: calendarInstant("2026-11-01T04:00:00Z"), end: calendarInstant("2026-11-02T05:00:00Z"))
    #expect(fullDay.window(on: fall, timeZone: zone) == fall)
    let springTicks = fullDay.ticks(on: spring, timeZone: zone, maximumCount: 25)
    #expect(!springTicks.contains(where: { $0.hour == 2 }))
    #expect(abs(try #require(springTicks.first(where: { $0.hour == 3 })).position - 2.0 / 23) < 0.000001)
    #expect(abs(try #require(springTicks.first(where: { $0.hour == 12 })).position - 11.0 / 23) < 0.000001)
    let fallTicks = fullDay.ticks(on: fall, timeZone: zone, maximumCount: 25)
    #expect(abs(try #require(fallTicks.first(where: { $0.hour == 12 })).position - 13.0 / 25) < 0.000001)
    #expect(CalendarDisplayHours().tickHours(maximumCount: 4) == [8, 12, 16, 18])
}

@Test func calendarOverviewPacksFullLabelsAndDurationBarsWithoutCollisions() {
    let layout = CalendarOverviewArrangement(labels: [
        .init(start: 0.1, end: 0.15, width: 90, height: 12),
        .init(start: 0.2, end: 0.3, width: 180, height: 24),
        .init(start: 0.8, end: 0.9, width: 90, height: 12),
        .init(start: 1, end: 1, width: 500, height: 36)
    ], width: 300)
    #expect(layout.placements[0].x == 30 && layout.placements[0].y == 0)
    #expect(layout.placements[1].x == 60 && layout.placements[1].y == 27)
    #expect(layout.placements[2].x == 210 && layout.placements[2].y == 0)
    #expect(layout.placements[3].x == 0 && layout.placements[3].width == 300)
    #expect(layout.placements[3].barX == 298 && layout.placements[3].barWidth == 2)
    #expect(abs(layout.placements[1].barWidth - 30) < 0.000001)
    #expect(layout.height == 109)
}

@Test func calendarSnapshotColorChangesRefreshWithoutChangingIdentity() throws {
    let date = Date(timeIntervalSince1970: 0)
    let red = try #require(CalendarColor(red: 1, green: 0, blue: 0))
    let first = CalendarEventSnapshot(calendarID: "one", eventID: "event", title: "Title", calendarTitle: "Calendar", start: date, end: date, color: red)
    let second = CalendarEventSnapshot(calendarID: "one", eventID: "event", title: "Title", calendarTitle: "Calendar", start: date, end: date)
    #expect(first.id == second.id && first != second)
    #expect(CalendarColor(red: .nan, green: 0, blue: 0) == nil)
    #expect(CalendarColor(red: 2, green: 0, blue: 0) == nil)
}
