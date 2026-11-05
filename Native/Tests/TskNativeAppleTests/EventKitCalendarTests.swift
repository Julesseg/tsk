import Foundation
import Testing
import TskCore
@testable import TskNative
#if canImport(EventKit)
@preconcurrency import EventKit
#endif

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
