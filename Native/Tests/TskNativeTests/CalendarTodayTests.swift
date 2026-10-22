import Foundation
import Testing
import TskCore
@testable import TskNative
#if canImport(EventKit)
@preconcurrency import EventKit
#endif

@Test func calendarTodayReadAndFailureLeaveRealReplicaBytesAndReopenedTasksUnchanged() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSince1970: 1792144800)
    let manager = TaskChampionSession.makeManager(directory: directory, now: { now })
    let task = try await manager.create(TaskDraft(description: "Calendar does not write tasks", attributes: ["scheduled": "1792108800", "due": "1792396800", "wait": "1792310400", "opaque": "e\u{301} café", "annotation_1792015200": "Preserve notes"]))
    let sqlite = directory.appendingPathComponent("taskchampion.sqlite3")
    let before = try Data(contentsOf: sqlite)
    let source = NativeCalendarFixtureSource(event: CalendarEventSnapshot(calendarID: "owned-test", eventID: "distinct-from-task", title: "Read-only event", calendarTitle: "Test", start: now, end: now.addingTimeInterval(3600)))
    #expect(await manager.todayCalendar(from: source).events.count == 1)
    #expect(try Data(contentsOf: sqlite) == before)
    await source.fail()
    #expect(await manager.todayCalendar(from: source).readError != nil)
    #expect(try Data(contentsOf: sqlite) == before)
    let reopened = TaskChampionSession.makeManager(directory: directory)
    #expect(try await reopened.tasks() == [task])
    #expect(try await reopened.task(id: task.id) == task)
    _ = try await reopened.complete(id: task.id)
    #expect(try await reopened.task(id: task.id).status == "completed")
}

private actor NativeCalendarFixtureSource: CalendarEventSource {
    let event: CalendarEventSnapshot
    var failing = false
    init(event: CalendarEventSnapshot) { self.event = event }
    func fail() { failing = true }
    func authorization() -> CalendarReadAuthorization { .fullAccess }
    func requestReadAccess() {}
    func events(in window: DateInterval) throws -> [CalendarEventSnapshot] { if failing { throw CocoaError(.fileReadUnknown) }; return [event] }
}

#if canImport(EventKit)
@Test @available(macOS 14.0, *)
func eventKitCalendarSnapshotValidationRunsOffMainActorWithoutRequestingAccess() async throws {
    await Task.detached {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Unsaved owned event"
        event.startDate = Date(timeIntervalSince1970: 1792144800)
        event.endDate = event.startDate.addingTimeInterval(3600)
        #expect(throws: CalendarReadError.invalidEvent) { try EventKitCalendarSource.snapshot(event) }
    }.value
}
#endif

#if canImport(EventKit)
import CoreGraphics

@Test func calendarSourceCarriesSRGBAndGrayscaleColorsWithoutRequiringPermission() throws {
    let color = try #require(EventKitCalendarSource.calendarColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 0.6)))
    #expect(abs(color.red - 0.2) < 0.00001 && abs(color.green - 0.4) < 0.00001 && abs(color.blue - 0.8) < 0.00001)
    #expect(abs(color.alpha - 0.6) < 0.00001)
    let gray = try #require(EventKitCalendarSource.calendarColor(CGColor(gray: 0.5, alpha: 1)))
    #expect(abs(gray.red - gray.green) < 0.00001 && abs(gray.green - gray.blue) < 0.00001)
    #expect(EventKitCalendarSource.calendarColor(nil) == nil)
}
#endif
