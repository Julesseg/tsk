#if canImport(EventKit)
import Foundation
@preconcurrency import EventKit
import TskCore

public enum CalendarReadError: Error, LocalizedError, Equatable, Sendable {
    case accessRequired, invalidWindow, invalidEvent
    public var errorDescription: String? {
        switch self {
        case .accessRequired: "Calendar read access is unavailable. Your tasks are still available."
        case .invalidWindow: "Today's Calendar date window is invalid."
        case .invalidEvent: "EventKit returned an event without its calendar, identity, or dates. Try refreshing Calendar."
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
public actor EventKitCalendarSource: CalendarEventSource {
    private let store = EKEventStore()
    public init() {}

    public func authorization() -> CalendarReadAuthorization { Self.currentAuthorization() }

    public func requestReadAccess() async throws {
        guard try await store.requestFullAccessToEvents() else { throw CalendarReadError.accessRequired }
        store.reset()
    }

    public func events(in window: DateInterval) throws -> [CalendarEventSnapshot] {
        guard Self.currentAuthorization() == .fullAccess else { throw CalendarReadError.accessRequired }
        guard window.start.timeIntervalSince1970.isFinite, window.end.timeIntervalSince1970.isFinite, window.duration > 0 else { throw CalendarReadError.invalidWindow }
        store.reset()
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let values = try store.events(matching: predicate).map(Self.snapshot)
        guard Self.currentAuthorization() == .fullAccess else { throw CalendarReadError.accessRequired }
        return values
    }

    nonisolated static func currentAuthorization() -> CalendarReadAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .fullAccess
        case .denied: .denied
        case .restricted: .restricted
        case .writeOnly: .writeOnly
        @unknown default: .unavailable
        }
    }

    nonisolated static func snapshot(_ event: EKEvent) throws -> CalendarEventSnapshot {
        guard let calendar = event.calendar, let start = event.startDate, let end = event.endDate,
              let identity = event.eventIdentifier, !identity.isEmpty else { throw CalendarReadError.invalidEvent }
        return CalendarEventSnapshot(calendarID: calendar.calendarIdentifier, eventID: identity, title: event.title ?? "", calendarTitle: calendar.title, location: event.location, start: start, end: end, isAllDay: event.isAllDay, isCanceled: event.status == .canceled)
    }
}
#endif
