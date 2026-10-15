#if canImport(EventKit)
import Foundation
@preconcurrency import EventKit
import TskCore

public enum ReminderAccessError: Error, LocalizedError, Sendable {
    case accessRequired
    case missingList
    case fetchFailed
    public var errorDescription: String? {
        switch self {
        case .accessRequired: "Reminders access is unavailable. Allow full Reminders access in Settings, then try again."
        case .missingList: "A selected Reminders list is no longer available. Refresh the lists and select again."
        case .fetchFailed: "EventKit could not fetch reminders. No copy was started. Try again."
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor public final class EventKitReminderSource: ReminderSource {
    let store: EKEventStore
    public init() { store = EKEventStore() }

    public func requestAccess() async throws {
        guard try await store.requestFullAccessToReminders() else { throw ReminderAccessError.accessRequired }
    }

    public func lists() async throws -> [ReminderList] {
        try requireAccess()
        return store.calendars(for: .reminder).map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func incompleteReminders(in listIDs: [String]) async throws -> [ReminderSnapshot] {
        try requireAccess()
        let calendars = try listIDs.map { id in
            guard let calendar = store.calendar(withIdentifier: id), calendar.allowedEntityTypes.contains(.reminder) else { throw ReminderAccessError.missingList }
            return calendar
        }
        guard !calendars.isEmpty else { throw ReminderImportError.noLists }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        let result: [ReminderSnapshot]? = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders?.map { item in
                    ReminderSnapshot(listID: item.calendar.calendarIdentifier, title: item.title ?? "", notes: item.notes,
                                     url: item.url?.absoluteString, priority: item.priority, start: item.startDateComponents,
                                     due: item.dueDateComponents, isCompleted: item.isCompleted,
                                     recurrenceDescription: item.recurrenceRules.flatMap { $0.isEmpty ? nil : $0.map { String(describing: $0) }.joined(separator: "; ") })
                })
            }
        }
        try requireAccess()
        guard let result else { throw ReminderAccessError.fetchFailed }
        return result
    }

    private func requireAccess() throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { throw ReminderAccessError.accessRequired }
    }
}
#endif
