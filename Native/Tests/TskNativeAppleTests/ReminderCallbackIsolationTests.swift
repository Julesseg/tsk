#if canImport(EventKit)
@preconcurrency import EventKit
import Foundation
import Testing
@testable import TskNative

@Test @available(macOS 14.0, *)
func eventKitFetchCallbackTransfersOnlyIdentifiersFromABackgroundExecutor() async {
    let values = await Task.detached {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Unsaved callback isolation fixture"
        let expected = [reminder.calendarItemIdentifier]
        let actual: [String]? = await withCheckedContinuation { continuation in
            EventKitReminderSource.identifierCallback(continuation)([reminder])
        }
        let missing: [String]? = await withCheckedContinuation { continuation in
            EventKitReminderSource.identifierCallback(continuation)(nil)
        }
        let empty: [String]? = await withCheckedContinuation { continuation in
            EventKitReminderSource.identifierCallback(continuation)([])
        }
        return (expected, actual, missing, empty)
    }.value
    #expect(values.1 == values.0)
    #expect(values.2 == nil)
    #expect(values.3 == [])
}
#endif
