#if DEBUG && canImport(EventKit) && targetEnvironment(simulator)
import Foundation
import TskCore
@preconcurrency import EventKit

@available(iOS 17.0, *)
@MainActor public enum EventKitRecurringReminderFixture {
    public static func prepare(source: EventKitReminderSource, token: String) async throws -> String {
        guard UUID(uuidString: token) != nil else { throw CocoaError(.coderInvalidValue) }
        source.recordAccessDiagnostic("reminders.recurring-fixture.prepare.begin")
        try EventKitReminderFixture.clean(source: source, token: token)
        let store = source.store
        guard let local = store.sources.first(where: { $0.sourceType == .local }) else {
            throw NSError(domain: "tsk.EventKitFixture", code: 34, userInfo: [NSLocalizedDescriptionKey: "No local source is available in the isolated simulator. Personal accounts are not a fallback."])
        }
        let selected = EKCalendar(for: .reminder, eventStore: store)
        selected.source = local; selected.title = "tsk fixture \(token) recurrence34"
        try store.saveCalendar(selected, commit: true)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2030, month: 1, day: 2, hour: 9, minute: 0, second: 0)
        func seed(_ title: String, interval: Int) throws {
            let item = EKReminder(eventStore: store)
            item.calendar = selected; item.title = title; item.priority = 1
            item.notes = "  Fixture notes\nsecond line  "; item.url = URL(string: "https://example.com/reminder")
            item.startDateComponents = first; item.dueDateComponents = first
            item.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: interval, end: nil))
            try store.save(item, commit: true)
        }
        try seed("Weekly current anchor", interval: 1)
        var completedSequence: [[String: Any]] = []
        for _ in 0..<5 {
            let current = try await next(store, selected, title: "Weekly current anchor")
            completedSequence.append(record(current))
            current.isCompleted = true; try store.save(current, commit: true)
            try await Task.sleep(for: .milliseconds(300))
        }
        let current = try await next(store, selected, title: "Weekly current anchor")
        _ = try write(["completedSequence": completedSequence, "currentAnchor": record(current), "sourceType": local.sourceType.rawValue], token: token)
        guard current.dueDateComponents?.month == 2, current.dueDateComponents?.day == 6 else {
            throw NSError(domain: "tsk.EventKitFixture", code: 34, userInfo: [NSLocalizedDescriptionKey: "The real current incomplete occurrence did not advance to the verified Feb6 anchor. See captured source fields."])
        }
        try seed("Unsupported two-week rule", interval: 2)
        let all = await fetch(store, selected)
        _ = try write(["completedSequence": completedSequence, "currentAnchor": record(current), "beforeImport": all.map(record), "sourceType": local.sourceType.rawValue], token: token)
        guard all.filter(\.isCompleted).count == 5, all.count == 7 else { throw CocoaError(.fileReadCorruptFile) }
        return try write(["completedSequence": completedSequence, "currentAnchor": record(current), "beforeImport": all.map(record), "sourceType": local.sourceType.rawValue], token: token)
    }

    public static func verify(source: EventKitReminderSource, token: String, moved: Bool) async throws -> String {
        guard UUID(uuidString: token) != nil,
              let list = source.store.calendars(for: .reminder).first(where: { $0.title == "tsk fixture \(token) recurrence34" }) else { throw CocoaError(.fileReadCorruptFile) }
        let file = evidenceURL(token)
        var evidence = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
        guard let before = evidence["beforeImport"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        let identifier = list.calendarIdentifier
        source.store.reset()
        guard let currentList = source.store.calendar(withIdentifier: identifier) else { throw CocoaError(.fileReadCorruptFile) }
        let after = await fetch(source.store, currentList).map(record)
        evidence["afterImport"] = after
        _ = try write(evidence, token: token)
        func sorted(_ records: [[String: Any]]) throws -> Data {
            let encoded = try records.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
            return encoded.sorted { $0.lexicographicallyPrecedes($1) }.reduce(into: Data()) { $0.append($1) }
        }
        let completedBefore = before.filter { $0["completed"] as? Bool == true }
        let completedAfter = after.filter { $0["completed"] as? Bool == true }
        let unsupportedBefore = before.filter { $0["title"] as? String == "Unsupported two-week rule" }
        let unsupportedAfter = after.filter { $0["title"] as? String == "Unsupported two-week rule" }
        guard completedBefore.count == 5, try sorted(completedBefore) == sorted(completedAfter),
              try sorted(unsupportedBefore) == sorted(unsupportedAfter) else { throw CocoaError(.fileReadCorruptFile) }
        if moved {
            guard after.count == 6, !after.contains(where: { $0["title"] as? String == "Weekly current anchor" && $0["completed"] as? Bool == false }) else { throw CocoaError(.fileReadCorruptFile) }
        } else { guard try sorted(before) == sorted(after) else { throw CocoaError(.fileReadCorruptFile) } }
        evidence["afterImport"] = after
        evidence["recurringImportScope"] = moved ? "Current recurring remainder removed; five completed history records and unsupported source unchanged" : "Copy left current recurring remainder, five completed history records and unsupported source unchanged"
        return try write(evidence, token: token)
    }

    private static func next(_ store: EKEventStore, _ list: EKCalendar, title: String) async throws -> EKReminder {
        for _ in 0..<30 {
            if let item = await fetch(store, list).first(where: { !$0.isCompleted && $0.title == title }) { return item }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw NSError(domain: "tsk.EventKitFixture", code: 34, userInfo: [NSLocalizedDescriptionKey: "The isolated weekly source did not expose the next incomplete occurrence."])
    }
    private static func fetch(_ store: EKEventStore, _ list: EKCalendar) async -> [EKReminder] {
        let predicate = store.predicateForReminders(in: [list])
        let references: [String]? = await withCheckedContinuation { store.fetchReminders(matching: predicate, completion: EventKitReminderSource.identifierCallback($0)) }
        return (references ?? []).compactMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
    }
    private static func record(_ item: EKReminder) -> [String: Any] {
        let snapshot = EventKitReminderSource.snapshot(item)
        return ["title": snapshot.title, "notes": snapshot.notes ?? "", "url": snapshot.url ?? "", "priority": snapshot.priority, "completed": snapshot.isCompleted, "start": ReminderFixtureDiagnostics.components(snapshot.start), "due": ReminderFixtureDiagnostics.components(snapshot.due), "mappingChecks": ReminderRecurrenceMapping.validationChecks(for: snapshot), "startDueStructurallyEqual": snapshot.start == snapshot.due, "recurrence": snapshot.recurrenceDescription as Any? ?? NSNull(), "sourceType": snapshot.sourceType as Any? ?? NSNull()]
    }
    private static func evidenceURL(_ token: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("reminders-fixture-\(token).json")
    }
    private static func write(_ output: [String: Any], token: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: evidenceURL(token), options: .atomic)
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
