#if canImport(EventKit)
import Foundation
@preconcurrency import EventKit
import TskCore

public enum ReminderAccessError: Error, LocalizedError, Sendable {
    case accessRequired
    case missingList
    case fetchFailed
    case sourceChanged
    case removalUnconfirmed
    public var errorDescription: String? {
        switch self {
        case .accessRequired: "Reminders access is unavailable. Allow full Reminders access in Settings, then try again."
        case .missingList: "A selected Reminders list is no longer available. Refresh the lists and select again."
        case .fetchFailed: "EventKit could not fetch reminders. No copy was started. Try again."
        case .sourceChanged: "The source reminder changed or is no longer writable. It was not removed. Review it before retrying."
        case .removalUnconfirmed: "EventKit did not confirm that the source reminder was removed. Review Reminders before retrying."
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor public final class EventKitReminderSource: ReminderMoveSource {
    let store: EKEventStore
    #if DEBUG && targetEnvironment(simulator)
    public var fixtureBeforeRemoval: (@MainActor @Sendable () async throws -> Void)?
    #endif
    public init() { store = EKEventStore() }

    public func requestAccess() async throws {
        guard try await store.requestFullAccessToReminders() else { throw ReminderAccessError.accessRequired }
    }

    public func lists() async throws -> [ReminderList] {
        try requireAccess()
        return store.calendars(for: .reminder).map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func incompleteReminders(in listIDs: [String]) async throws -> [ReminderSnapshot] {
        try await fetch(in: listIDs).map(\.snapshot)
    }

    public func moveCandidates(in listIDs: [String]) async throws -> [ReminderMoveCandidate] {
        try await fetch(in: listIDs).map { value in
            ReminderMoveCandidate(snapshot: value.snapshot, removeSource: { try await self.removeSource(reference: value.reference, expected: value.snapshot) })
        }
    }

    private func fetch(in listIDs: [String]) async throws -> [ReminderTransferValue] {
        try requireAccess()
        let calendars = try listIDs.map { id in
            guard let calendar = store.calendar(withIdentifier: id), calendar.allowedEntityTypes.contains(.reminder) else { throw ReminderAccessError.missingList }
            return calendar
        }
        guard !calendars.isEmpty else { throw ReminderImportError.noLists }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        let identifiers: [String]? = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate, completion: Self.identifierCallback(continuation))
        }
        try requireAccess()
        guard let identifiers else { throw ReminderAccessError.fetchFailed }
        store.reset()
        let result: [ReminderTransferValue] = try identifiers.compactMap { reference in
            guard let item = store.calendarItem(withIdentifier: reference) as? EKReminder,
                  listIDs.contains(item.calendar.calendarIdentifier) else { throw ReminderAccessError.sourceChanged }
            guard !item.isCompleted else { return nil }
            return ReminderTransferValue(reference: reference, snapshot: Self.snapshot(item))
        }
        return result.sorted { lhs, rhs in
            if !lhs.snapshot.title.matchesBytes(rhs.snapshot.title) { return UTF8String(lhs.snapshot.title) < UTF8String(rhs.snapshot.title) }
            return lhs.reference < rhs.reference
        }
    }

    private func removeSource(reference: String, expected: ReminderSnapshot) async throws {
        try Task.checkCancellation()
        #if DEBUG && targetEnvironment(simulator)
        try await fixtureBeforeRemoval?()
        #endif
        try Task.checkCancellation()
        try requireAccess()
        store.reset()
        guard let current = store.calendarItem(withIdentifier: reference) as? EKReminder,
              current.calendar.allowsContentModifications, Self.snapshot(current) == expected else { throw ReminderAccessError.sourceChanged }
        try store.remove(current, commit: true)
        store.reset()
        guard store.calendarItem(withIdentifier: reference) == nil else { throw ReminderAccessError.removalUnconfirmed }
    }

    nonisolated static func identifierCallback(_ continuation: CheckedContinuation<[String]?, Never>) -> @Sendable ([EKReminder]?) -> Void {
        { reminders in continuation.resume(returning: reminders?.map(\.calendarItemIdentifier)) }
    }

    private static func snapshot(_ item: EKReminder) -> ReminderSnapshot {
        ReminderSnapshot(listID: item.calendar.calendarIdentifier, title: item.title ?? "", notes: item.notes,
                         url: item.url?.absoluteString, priority: item.priority, start: item.startDateComponents,
                         due: item.dueDateComponents, isCompleted: item.isCompleted,
                         recurrenceDescription: recurrenceSignature(item.recurrenceRules))
    }

    private static func recurrenceSignature(_ rules: [EKRecurrenceRule]?) -> String? {
        guard let rules, !rules.isEmpty else { return nil }
        let values = rules.map { rule in
            ["frequency": rule.frequency.rawValue, "interval": rule.interval, "calendar": rule.calendarIdentifier,
             "firstDayOfWeek": rule.firstDayOfTheWeek,
             "weekdays": rule.daysOfTheWeek?.map { ["day": $0.dayOfTheWeek.rawValue, "ordinal": $0.weekNumber] } ?? [],
             "monthdays": rule.daysOfTheMonth ?? [], "yeardays": rule.daysOfTheYear ?? [], "yearweeks": rule.weeksOfTheYear ?? [],
             "months": rule.monthsOfTheYear ?? [], "positions": rule.setPositions ?? [],
             "endDate": rule.recurrenceEnd?.endDate?.timeIntervalSince1970 as Any? ?? NSNull(),
             "endCount": rule.recurrenceEnd?.occurrenceCount ?? 0] as [String: Any]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return "Unrecognized recurrence rule" }
        return String(decoding: data, as: UTF8.self)
    }

    private func requireAccess() throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { throw ReminderAccessError.accessRequired }
    }
}

private struct ReminderTransferValue: Sendable {
    let reference: String
    let snapshot: ReminderSnapshot
}
#endif
