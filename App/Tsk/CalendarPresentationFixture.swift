#if DEBUG && targetEnvironment(simulator)
import Foundation
import TskCore

actor CalendarPresentationFixture: CalendarEventSource {
    enum State: String { case populated, many, empty, notDetermined, denied, restricted, writeOnly, unavailable, failure }
    private let state: State
    private var access: CalendarReadAuthorization
    private var shouldFail: Bool

    init?(environment: [String: String]) {
        guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1",
              environment["TSK_TEST_REPLICA_NAME"].flatMap(UUID.init(uuidString:)) != nil,
              let raw = environment["TSK_TEST_CALENDAR_PRESENTATION"], let state = State(rawValue: raw) else { return nil }
        self.state = state
        shouldFail = state == .failure
        access = switch state {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .writeOnly: .writeOnly
        case .unavailable: .unavailable
        default: .fullAccess
        }
    }

    func authorization() -> CalendarReadAuthorization { access }
    func requestReadAccess() { if access == .notDetermined || access == .writeOnly || access == .unavailable { access = .fullAccess } }
    func events(in window: DateInterval) throws -> [CalendarEventSnapshot] {
        if shouldFail { shouldFail = false; throw CocoaError(.fileReadUnknown) }
        if state == .empty { return [] }
        func event(_ id: String, _ title: String, start: Date, end: Date, allDay: Bool = false) -> CalendarEventSnapshot {
            CalendarEventSnapshot(calendarID: "presentation", eventID: id, title: title, calendarTitle: "Hidden calendar name", location: "Hidden event location", start: start, end: end, isAllDay: allDay)
        }
        var events = [
            event("all-day", "Team offsite", start: window.start, end: window.end, allDay: true),
            event("spanning", "Overnight support", start: window.start.addingTimeInterval(-3600), end: window.end.addingTimeInterval(3600)),
            event("timed", "Design review with the product team", start: window.start.addingTimeInterval(36000), end: window.start.addingTimeInterval(39600)),
            event("instant", "", start: window.start.addingTimeInterval(43200), end: window.start.addingTimeInterval(43200))
        ]
        if state == .many {
            for index in 1...18 {
                let start = window.start.addingTimeInterval(Double(45000 + index * 900))
                events.append(event("extra-\(index)", "Planning session \(index)", start: start, end: start.addingTimeInterval(900)))
            }
        }
        return events
    }
}
#endif
