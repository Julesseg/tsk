import Foundation

public enum CalendarReadAuthorization: Equatable, Sendable {
    case notDetermined, fullAccess, denied, restricted, writeOnly, unavailable
}

public protocol CalendarEventSource: Sendable {
    func authorization() async -> CalendarReadAuthorization
    func requestReadAccess() async throws
    func events(in window: DateInterval) async throws -> [CalendarEventSnapshot]
}

public struct CalendarEventIdentity: Hashable, Sendable {
    public let calendarID: UTF8String
    public let eventID: UTF8String
    public let occurrenceStart: Date
}

public struct CalendarEventSnapshot: Equatable, Sendable, Identifiable {
    public let calendarID: String
    public let eventID: String
    public let title: String
    public let calendarTitle: String
    public let location: String?
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let isCanceled: Bool
    public var id: CalendarEventIdentity { CalendarEventIdentity(calendarID: UTF8String(calendarID), eventID: UTF8String(eventID), occurrenceStart: start) }

    public init(calendarID: String, eventID: String, title: String, calendarTitle: String, location: String? = nil, start: Date, end: Date, isAllDay: Bool = false, isCanceled: Bool = false) {
        self.calendarID = calendarID; self.eventID = eventID; self.title = title; self.calendarTitle = calendarTitle; self.location = location
        self.start = start; self.end = end; self.isAllDay = isAllDay; self.isCanceled = isCanceled
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title.matchesBytes(rhs.title) && lhs.calendarTitle.matchesBytes(rhs.calendarTitle)
            && lhs.location.map { UTF8String($0) } == rhs.location.map { UTF8String($0) }
            && lhs.end == rhs.end && lhs.isAllDay == rhs.isAllDay && lhs.isCanceled == rhs.isCanceled
    }
}

public struct TodayCalendarEvent: Equatable, Sendable, Identifiable {
    public let event: CalendarEventSnapshot
    public let visibleStart: Date
    public let visibleEnd: Date
    public let continuesBefore: Bool
    public let continuesAfter: Bool
    public let endsAtDayBoundary: Bool
    public var id: CalendarEventIdentity { event.id }
    public var isInstant: Bool { event.start == event.end }
}

public struct TodayCalendarSnapshot: Equatable, Sendable {
    public let day: DateInterval?
    public let timeZone: TimeZone
    public let authorization: CalendarReadAuthorization
    public let events: [TodayCalendarEvent]
    public let readError: String?
    public let omittedEntryCount: Int
}

public extension TaskManager {
    func todayCalendar(from source: any CalendarEventSource, requestingAccess: Bool = false) async -> TodayCalendarSnapshot {
        var dateCalendar = calendar
        dateCalendar.timeZone = calendar.timeZone
        var access = await source.authorization()
        var day = dateCalendar.dateInterval(of: .day, for: now())
        func snapshot(events: [TodayCalendarEvent] = [], error: String? = nil, omitted: Int = 0) -> TodayCalendarSnapshot {
            TodayCalendarSnapshot(day: day, timeZone: dateCalendar.timeZone, authorization: access, events: events, readError: error, omittedEntryCount: omitted)
        }
        var requestingPermission = false
        do {
            if requestingAccess && access != .fullAccess {
                requestingPermission = true
                try await source.requestReadAccess()
                requestingPermission = false
                access = await source.authorization()
            }
            day = dateCalendar.dateInterval(of: .day, for: now())
            guard access == .fullAccess else { return snapshot() }
            guard let window = day, window.duration > 0 else { return snapshot(error: "Today's Calendar date window could not be determined.") }
            let values = try await source.events(in: window)
            access = await source.authorization()
            guard access == .fullAccess else { return snapshot() }
            var seen = Set<CalendarEventIdentity>()
            var omitted = 0
            let visible: [TodayCalendarEvent] = values.compactMap { event in
                guard !event.isCanceled else { return nil }
                guard event.start.timeIntervalSince1970.isFinite, event.end.timeIntervalSince1970.isFinite,
                      event.end >= event.start, !event.calendarID.isEmpty, !event.eventID.isEmpty else { omitted += 1; return nil }
                let overlaps = event.start == event.end ? event.start >= window.start && event.start < window.end : event.start < window.end && event.end > window.start
                guard overlaps else { return nil }
                guard seen.insert(event.id).inserted else { omitted += 1; return nil }
                return TodayCalendarEvent(event: event, visibleStart: max(event.start, window.start), visibleEnd: min(event.end, window.end), continuesBefore: event.start < window.start, continuesAfter: event.end > window.end, endsAtDayBoundary: event.end >= window.end)
            }.sorted { lhs, rhs in
                if lhs.event.isAllDay != rhs.event.isAllDay { return lhs.event.isAllDay }
                if lhs.visibleStart != rhs.visibleStart { return lhs.visibleStart < rhs.visibleStart }
                if lhs.visibleEnd != rhs.visibleEnd { return lhs.visibleEnd < rhs.visibleEnd }
                if UTF8String(lhs.event.title) != UTF8String(rhs.event.title) { return UTF8String(lhs.event.title) < UTF8String(rhs.event.title) }
                if lhs.id.calendarID != rhs.id.calendarID { return lhs.id.calendarID < rhs.id.calendarID }
                return lhs.id.eventID < rhs.id.eventID
            }
            return snapshot(events: visible, omitted: omitted)
        } catch {
            access = await source.authorization()
            return snapshot(error: access == .fullAccess || (requestingPermission && access != .denied && access != .restricted) ? error.localizedDescription : nil)
        }
    }
}
