#if DEBUG && canImport(EventKit) && targetEnvironment(simulator)
import Foundation
@preconcurrency import EventKit

@available(iOS 17.0, *)
@MainActor public enum EventKitReminderFixture {
    public static func clean(source: EventKitReminderSource, token: String) throws {
        guard UUID(uuidString: token) != nil else { throw CocoaError(.coderInvalidValue) }
        for list in source.store.calendars(for: .reminder) where list.title.hasPrefix("tsk fixture \(token) ") {
            try source.store.removeCalendar(list, commit: true)
        }
    }

    public static func prepare(source: EventKitReminderSource, token: String) async throws -> String {
        guard UUID(uuidString: token) != nil else { throw CocoaError(.coderInvalidValue) }
        let store = source.store
        var output: [String: Any] = ["sources": store.sources.map { ["title": $0.title, "type": $0.sourceType.rawValue] }]
        output["authorizationAtPreparation"] = EKEventStore.authorizationStatus(for: .reminder).rawValue
        var stage = "create disposable lists and reminders"
        do {
            try clean(source: source, token: token)
            guard let local = store.sources.first(where: { $0.sourceType == .local }) else {
                throw NSError(domain: "tsk.EventKitFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No local Reminders source is available in this isolated simulator. Personal accounts are not used as a fallback."])
            }
            func list(_ suffix: String) throws -> EKCalendar {
                let list = EKCalendar(for: .reminder, eventStore: store)
                list.source = local; list.title = "tsk fixture \(token) \(suffix)"
                try store.saveCalendar(list, commit: true)
                return list
            }
            let selected = try list("selected"), unselected = try list("unselected"), sequenceList = try list("sequence")
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let start = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2030, month: 1, day: 2, hour: 9, minute: 0, second: 0)
            let due = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2030, month: 1, day: 3, hour: 10, minute: 30, second: 0)
            func reminder(_ title: String, in list: EKCalendar, priority: Int = 0, completed: Bool = false, recurring: Bool = false, recurrenceInterval: Int = 1) throws {
                let item = EKReminder(eventStore: store)
                item.calendar = list; item.title = title; item.priority = priority
                item.notes = "  Fixture notes\nsecond line  "; item.url = URL(string: "https://example.com/reminder")
                item.startDateComponents = start; item.dueDateComponents = recurring ? start : due
                if recurring { item.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: recurrenceInterval, end: nil)) }
                item.isCompleted = completed
                try store.save(item, commit: true)
            }
            try reminder("Copy fixture H", in: selected, priority: 1)
            try reminder("Copy fixture none", in: selected)
            try reminder("Exclude completed", in: selected, completed: true)
            try reminder("Exclude unselected", in: unselected)
            try reminder("Skip recurring", in: selected, recurring: true, recurrenceInterval: 2)
            try reminder("Weekly UTC sequence", in: sequenceList, recurring: true)
            output["selectedBeforeCopy"] = await fetch(store, selected, incomplete: false).map(summary)
            var sequence: [[String: Any]] = []
            for index in 0..<5 {
                stage = "complete disposable weekly occurrence \(index + 1)"
                guard let current = try await nextIncomplete(store, sequenceList) else { break }
                sequence.append(summary(current))
                output["completionSequence"] = sequence
                current.isCompleted = true
                try store.save(current, commit: true)
                try await Task.sleep(for: .milliseconds(300))
            }
            output["completionSequence"] = sequence
            output["beforeRemoval"] = await fetch(store, sequenceList, incomplete: false).map(summary)
            stage = "remove disposable incomplete weekly occurrence"
            output["authorizationBeforeRemoval"] = EKEventStore.authorizationStatus(for: .reminder).rawValue
            if let current = await fetch(store, sequenceList, incomplete: true).first {
                output["removalCandidate"] = summary(current)
                output["removalCandidateIdentifier"] = current.calendarItemIdentifier
                output["removalCalendarWritable"] = current.calendar.allowsContentModifications
                try store.remove(current, commit: true)
            }
            stage = "read disposable weekly history after removal"
            try await Task.sleep(for: .milliseconds(300))
            output["afterRemoval"] = await fetch(store, sequenceList, incomplete: false).map(summary)
            output["incompleteAfterRemoval"] = await fetch(store, sequenceList, incomplete: true).map(summary)
            guard sequence.count == 5 else { throw NSError(domain: "tsk.EventKitFixture", code: 2, userInfo: [NSLocalizedDescriptionKey: "The real EventKit recurrence sequence did not expose five incomplete occurrences."]) }
            output["fixtureStatus"] = "Real EventKit source, storage, five completions and removal observed"
        } catch {
            output["error"] = error.localizedDescription
            output["failedStage"] = stage
            output["errorDomain"] = (error as NSError).domain
            output["errorCode"] = (error as NSError).code
            output["authorizationAfterFailure"] = EKEventStore.authorizationStatus(for: .reminder).rawValue
            _ = try write(output, token: token)
            throw NSError(domain: "tsk.EventKitFixture", code: 3, userInfo: [NSLocalizedDescriptionKey: "The isolated Reminders fixture could not \(stage): \(error.localizedDescription). Full evidence was saved for this test."])
        }
        return try write(output, token: token)
    }

    public static func verifySourcesUnchanged(source: EventKitReminderSource, token: String) async throws -> String {
        let selected = try source.store.calendars(for: .reminder).first { $0.title == "tsk fixture \(token) selected" }.unwrapFixture()
        let items = await fetch(source.store, selected, incomplete: false)
        let evidenceURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("reminders-fixture-\(token).json")
        var evidence = try JSONSerialization.jsonObject(with: Data(contentsOf: evidenceURL)) as? [String: Any]
        guard let before = evidence?["selectedBeforeCopy"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        let after = items.map(summary)
        func sorted(_ values: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: values.sorted { ($0["title"] as? String ?? "") < ($1["title"] as? String ?? "") }, options: [.sortedKeys])
        }
        guard items.count == 4, items.filter(\.isCompleted).count == 1, try sorted(before) == sorted(after) else {
            throw NSError(domain: "tsk.EventKitFixture", code: 4, userInfo: [NSLocalizedDescriptionKey: "One-time copy changed the real source reminders."])
        }
        evidence?["selectedAfterCopy"] = after
        evidence?["copyPreservedSources"] = true
        if let evidence { _ = try write(evidence, token: token) }
        return "Verified four source reminders unchanged, including completed and recurring reminders."
    }

    public static func addCapture(source: EventKitReminderSource, token: String, title: String) throws {
        guard UUID(uuidString: token) != nil else { throw CocoaError(.coderInvalidValue) }
        let list = try source.store.calendars(for: .reminder).first { $0.title == "tsk fixture \(token) selected" }.unwrapFixture()
        let reminder = EKReminder(eventStore: source.store)
        reminder.calendar = list; reminder.title = title; reminder.notes = "Actual observed source change"
        try source.store.save(reminder, commit: true)
    }

    public static func editPendingIntoRecurring(source: EventKitReminderSource, token: String) async throws {
        guard UUID(uuidString: token) != nil else { throw CocoaError(.coderInvalidValue) }
        let list = try source.store.calendars(for: .reminder).first { $0.title == "tsk fixture \(token) selected" }.unwrapFixture()
        let item = try await fetch(source.store, list, incomplete: true).first { $0.title == "Copy fixture H" }.unwrapFixture()
        item.notes = "Externally edited before removal"
        item.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 2, end: nil))
        try source.store.save(item, commit: true)
    }

    public static func verifyMove(source: EventKitReminderSource, token: String, changed: Bool) async throws -> String {
        guard UUID(uuidString: token) != nil else { throw CocoaError(.coderInvalidValue) }
        let selected = try source.store.calendars(for: .reminder).first { $0.title == "tsk fixture \(token) selected" }.unwrapFixture()
        let unselected = try source.store.calendars(for: .reminder).first { $0.title == "tsk fixture \(token) unselected" }.unwrapFixture()
        let items = await fetch(source.store, selected, incomplete: false)
        let excluded = await fetch(source.store, unselected, incomplete: false)
        if changed {
            guard items.count == 4, items.contains(where: { $0.title == "Copy fixture H" && $0.notes == "Externally edited before removal" && !($0.recurrenceRules ?? []).isEmpty }),
                  items.contains(where: { $0.title == "Copy fixture none" && !$0.isCompleted }) else { throw CocoaError(.fileReadCorruptFile) }
        } else {
            guard items.count == 2, items.contains(where: { $0.title == "Exclude completed" && $0.isCompleted }),
                  items.contains(where: { $0.title == "Skip recurring" && !($0.recurrenceRules ?? []).isEmpty }) else { throw CocoaError(.fileReadCorruptFile) }
        }
        guard excluded.count == 1, excluded[0].title == "Exclude unselected", !excluded[0].isCompleted else { throw CocoaError(.fileReadCorruptFile) }
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("reminders-fixture-\(token).json")
        var output = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
        output["selectedAfterMove"] = items.map(summary); output["unselectedAfterMove"] = excluded.map(summary)
        output["moveScopeVerified"] = changed ? "Changed source and newly recurring rule preserved after durable destination save" : "Only two eligible sources removed; completed, unselected and recurring sources preserved"
        return try write(output, token: token)
    }

    private static func nextIncomplete(_ store: EKEventStore, _ list: EKCalendar) async throws -> EKReminder? {
        for _ in 0..<25 {
            if let item = await fetch(store, list, incomplete: true).first { return item }
            try await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }

    private static func fetch(_ store: EKEventStore, _ list: EKCalendar, incomplete: Bool) async -> [EKReminder] {
        let predicate = incomplete ? store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list]) : store.predicateForReminders(in: [list])
        let references: [String] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: ($0 ?? []).map(\.calendarItemIdentifier)) }
        }
        return references.compactMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
    }

    private static func summary(_ item: EKReminder) -> [String: Any] {
        ["title": item.title ?? "", "notes": item.notes ?? "", "url": item.url?.absoluteString ?? "", "priority": item.priority, "completed": item.isCompleted, "start": date(item.startDateComponents), "due": date(item.dueDateComponents),
         "rules": (item.recurrenceRules ?? []).map { rule in
             ["frequency": rule.frequency.rawValue, "interval": rule.interval, "firstDayOfWeek": rule.firstDayOfTheWeek,
              "calendarIdentifier": rule.calendarIdentifier, "weekdays": rule.daysOfTheWeek?.map { ["day": $0.dayOfTheWeek.rawValue, "week": $0.weekNumber] } ?? [],
              "monthdays": rule.daysOfTheMonth ?? [], "yeardays": rule.daysOfTheYear ?? [], "yearweeks": rule.weeksOfTheYear ?? [],
              "months": rule.monthsOfTheYear ?? [], "setPositions": rule.setPositions ?? [],
              "endDate": rule.recurrenceEnd?.endDate.map { ISO8601DateFormatter().string(from: $0) } ?? "nil", "endCount": rule.recurrenceEnd?.occurrenceCount ?? 0] as [String: Any]
         }]
    }

    private static func date(_ components: DateComponents?) -> [String: Any] {
        ReminderFixtureDiagnostics.components(components)
    }

    private static func write(_ output: [String: Any], token: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("reminders-fixture-\(token).json"), options: .atomic)
        return String(decoding: data, as: UTF8.self)
    }
}

private extension Optional {
    func unwrapFixture() throws -> Wrapped {
        guard let self else { throw NSError(domain: "tsk.EventKitFixture", code: 5, userInfo: [NSLocalizedDescriptionKey: "The owned fixture list is missing."]) }
        return self
    }
}
#endif
