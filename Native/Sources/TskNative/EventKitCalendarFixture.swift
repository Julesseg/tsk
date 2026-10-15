#if DEBUG && canImport(EventKit) && targetEnvironment(simulator)
import Foundation
@preconcurrency import EventKit
import TskCore

@available(iOS 17.0, *)
@MainActor public enum EventKitCalendarFixture {
    public static func prepare(token: String, day: DateInterval) throws {
        try validate(token)
        let store = EKEventStore()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarReadError.accessRequired }
        if store.calendars(for: .event).contains(where: { $0.title == name(token) }) { return }
        var evidence: [String: Any] = ["sources": store.sources.map { ["type": $0.sourceType.rawValue, "title": $0.title] }, "dayStart": day.start.timeIntervalSince1970, "dayEnd": day.end.timeIntervalSince1970, "timeZone": TimeZone.current.identifier]
        do {
            guard let local = store.sources.first(where: { $0.sourceType == .local }) else {
                throw NSError(domain: "tsk.CalendarFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No LOCAL Calendar source exists in this isolated simulator. Personal accounts are not used as fallback."])
            }
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = name(token); calendar.source = local
            try store.saveCalendar(calendar, commit: true)
            func add(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) throws {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar; event.title = title; event.startDate = start; event.endDate = end; event.isAllDay = allDay; event.location = "Owned fixture location"
                try store.save(event, span: .thisEvent, commit: true)
            }
            try add("Calendar fixture timed", day.start.addingTimeInterval(36000), day.start.addingTimeInterval(39600))
            try add("Calendar fixture all day", day.start, day.end, allDay: true)
            try add("Calendar fixture spanning", day.start.addingTimeInterval(-3600), day.end.addingTimeInterval(3600))
            try add("Calendar fixture boundary excluded", day.start.addingTimeInterval(-7200), day.start)
            try add("Calendar fixture tomorrow excluded", day.end, day.end.addingTimeInterval(3600))
            evidence["sourceType"] = local.sourceType.rawValue
            evidence["storedBeforeDisplay"] = summaries(store: store, calendar: calendar, day: day)
            try write(evidence, token: token)
        } catch {
            evidence["error"] = error.localizedDescription
            try write(evidence, token: token)
            throw error
        }
    }

    public static func verify(token: String, day: DateInterval, displayed: [CalendarEventSnapshot]) throws {
        try validate(token)
        let store = EKEventStore()
        guard let calendar = store.calendars(for: .event).first(where: { $0.title == name(token) }) else { throw CocoaError(.fileNoSuchFile) }
        var evidence = try JSONSerialization.jsonObject(with: Data(contentsOf: file(token))) as? [String: Any] ?? [:]
        let after = summaries(store: store, calendar: calendar, day: day)
        guard let before = evidence["storedBeforeDisplay"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        let originalAfter = after.filter { ($0["title"] as? String) != "Calendar fixture observed change" }
        guard try encoded(before) == encoded(originalAfter) else { throw NSError(domain: "tsk.CalendarFixture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Displaying Calendar changed owned source events."]) }
        let owned = displayed.filter { $0.calendarTitle == name(token) }
        guard owned.count >= 3, owned.contains(where: { $0.title == "Calendar fixture all day" && $0.isAllDay }),
              owned.contains(where: { $0.title == "Calendar fixture timed" }), owned.contains(where: { $0.title == "Calendar fixture spanning" }),
              !owned.contains(where: { $0.title.contains("excluded") }) else { throw NSError(domain: "tsk.CalendarFixture", code: 3, userInfo: [NSLocalizedDescriptionKey: "Actual Calendar Today display did not match stored fixture boundaries."]) }
        evidence["storedAfterDisplay"] = after
        evidence["displayed"] = owned.map { ["title": $0.title, "id": $0.eventID, "start": $0.start.timeIntervalSince1970, "end": $0.end.timeIntervalSince1970, "allDay": $0.isAllDay] as [String: Any] }
        evidence["readOnlyVerified"] = true
        try write(evidence, token: token)
    }

    public static func addObservedEvent(token: String, day: DateInterval) throws {
        try validate(token)
        let store = EKEventStore()
        guard let calendar = store.calendars(for: .event).first(where: { $0.title == name(token) }) else { throw CocoaError(.fileNoSuchFile) }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar; event.title = "Calendar fixture observed change"; event.startDate = day.start.addingTimeInterval(43200); event.endDate = day.start.addingTimeInterval(45000)
        try store.save(event, span: .thisEvent, commit: true)
    }

    public static func clean(token: String) throws {
        try validate(token)
        let store = EKEventStore()
        for calendar in store.calendars(for: .event) where calendar.title == name(token) { try store.removeCalendar(calendar, commit: true) }
    }

    private static func summaries(store: EKEventStore, calendar: EKCalendar, day: DateInterval) -> [[String: Any]] {
        store.events(matching: store.predicateForEvents(withStart: day.start.addingTimeInterval(-86400), end: day.end.addingTimeInterval(86400), calendars: [calendar])).map {
            ["id": $0.eventIdentifier ?? "", "title": $0.title ?? "", "start": $0.startDate.timeIntervalSince1970, "end": $0.endDate.timeIntervalSince1970, "allDay": $0.isAllDay, "location": $0.location ?? ""] as [String: Any]
        }.sorted { ($0["title"] as? String ?? "") < ($1["title"] as? String ?? "") }
    }
    private static func validate(_ token: String) throws { guard UUID(uuidString: token) != nil, ProcessInfo.processInfo.environment["TSK_UI_ISOLATED_SIMULATOR"] == "1" else { throw CocoaError(.coderInvalidValue) } }
    private static func name(_ token: String) -> String { "tsk Calendar fixture \(token)" }
    private static func file(_ token: String) -> URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("calendar-fixture-\(token).json") }
    private static func encoded(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    private static func write(_ value: Any, token: String) throws { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]).write(to: file(token), options: .atomic) }
}
#endif
