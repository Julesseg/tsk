#if canImport(EventKit)
import Foundation
@preconcurrency import EventKit
import TskCore

public enum ReminderAccessError: Error, LocalizedError, Sendable {
    case accessRequired
    case accessNotReady
    case missingList
    case fetchFailed
    case sourceChanged
    case removalUnconfirmed
    public var errorDescription: String? {
        switch self {
        case .accessNotReady: "Reminders access has been granted but is not ready yet. Try again."
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
    private let access = EventKitReminderAccessPolicy()
    #if DEBUG && targetEnvironment(simulator)
    public var fixtureBeforeRemoval: (@MainActor @Sendable () async throws -> Void)?
    private let diagnosticStoreID = UUID().uuidString
    private var authorizationSamples: Task<Void, Never>?
    private var authorizationSampleRequests = 0
    #endif
    public init() { store = EKEventStore() }

    public func requestAccess() async throws {
        guard try await access.requestAccess(authorization: { .init(EKEventStore.authorizationStatus(for: .reminder)) }, request: requestNativeAccess) else {
            throw ReminderAccessError.accessRequired
        }
    }

    private func requestNativeAccess() async throws -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        let requestID = UUID().uuidString
        let context = accessDiagnosticContext
        let trace = context == nil ? nil : TaskParticipantDiagnostics.begin("reminders.access")
        defer { TaskParticipantDiagnostics.end("reminders.access", id: trace) }
        recordAccessDiagnostic("reminders.access.begin", details: ["request": requestID])
        do {
            let granted: Bool = try await withCheckedThrowingContinuation { continuation in
                store.requestFullAccessToReminders(completion: Self.accessCallback(continuation, context: context, requestID: requestID))
            }
            recordAccessDiagnostic("reminders.access.returned", details: ["request": requestID, "granted": String(granted)])
            if granted, context != nil, authorizationSampleRequests < 3 {
                authorizationSampleRequests += 1
                authorizationSamples?.cancel()
                authorizationSamples = Task { @MainActor [weak self] in
                    for interval in [100, 400, 1500, 3000] {
                        do { try await Task.sleep(for: .milliseconds(interval)) } catch { return }
                        guard let self else { return }
                        self.recordAccessDiagnostic("reminders.access.publication-sample", details: ["request": requestID])
                    }
                }
            }
            return granted
        } catch {
            let native = error as NSError
            recordAccessDiagnostic("reminders.access.error", details: ["request": requestID, "errorDomain": native.domain, "errorCode": String(native.code)])
            throw error
        }
        #else
        return try await store.requestFullAccessToReminders()
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private var accessDiagnosticContext: [String: String]? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1",
              ["TSK_TEST_REMINDERS_FIXTURE", "TSK_TEST_REMINDERS_RECURRING_FIXTURE", "TSK_TEST_REMINDERS_VERIFY_TOKEN"].contains(where: { environment[$0].flatMap(UUID.init(uuidString:)) != nil }) else { return nil }
        return ["store": diagnosticStoreID]
    }

    public func recordAccessDiagnostic(_ stage: String, details: [String: String] = [:]) {
        guard var context = accessDiagnosticContext else { return }
        context.merge(details) { _, value in value }
        context["authorization"] = String(EKEventStore.authorizationStatus(for: .reminder).rawValue)
        context["mainThread"] = String(Thread.isMainThread)
        TaskParticipantDiagnostics.event(stage, details: context)
    }

    nonisolated private static func accessCallback(_ continuation: CheckedContinuation<Bool, any Error>, context: [String: String]?, requestID: String) -> @Sendable (Bool, (any Error)?) -> Void {
        { granted, error in
            if var context {
                context["request"] = requestID
                context["granted"] = String(granted)
                context["mainThread"] = String(Thread.isMainThread)
                context["authorization"] = String(EKEventStore.authorizationStatus(for: .reminder).rawValue)
                if let native = error as NSError? { context["errorDomain"] = native.domain; context["errorCode"] = String(native.code) }
                TaskParticipantDiagnostics.event("reminders.access.callback", details: context)
            }
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume(returning: granted) }
        }
    }
    #endif

    public func lists() async throws -> [ReminderList] {
        #if DEBUG && targetEnvironment(simulator)
        recordAccessDiagnostic("reminders.lists.begin")
        #endif
        try await requireAccess()
        let lists = store.calendars(for: .reminder).map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        #if DEBUG && targetEnvironment(simulator)
        recordAccessDiagnostic("reminders.lists.returned", details: ["count": String(lists.count)])
        #endif
        return lists
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
        try await requireAccess()
        let calendars = try listIDs.map { id in
            guard let calendar = store.calendar(withIdentifier: id), calendar.allowedEntityTypes.contains(.reminder) else { throw ReminderAccessError.missingList }
            return calendar
        }
        guard !calendars.isEmpty else { throw ReminderImportError.noLists }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        let identifiers: [String]? = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate, completion: Self.identifierCallback(continuation))
        }
        try await requireAccess()
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
        #if DEBUG && targetEnvironment(simulator)
        recordAccessDiagnostic("reminders.move.removal.begin")
        #endif
        try Task.checkCancellation()
        #if DEBUG && targetEnvironment(simulator)
        try await fixtureBeforeRemoval?()
        #endif
        try Task.checkCancellation()
        try await requireAccess()
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

    static func snapshot(_ item: EKReminder) -> ReminderSnapshot {
        ReminderSnapshot(listID: item.calendar.calendarIdentifier, title: item.title ?? "", notes: item.notes,
                         url: item.url?.absoluteString, priority: item.priority, start: item.startDateComponents,
                         due: item.dueDateComponents, isCompleted: item.isCompleted,
                         recurrenceDescription: recurrenceSignature(item.recurrenceRules), sourceType: item.calendar.source.sourceType.rawValue)
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

    private func requireAccess() async throws {
        guard try await access.requireAccess(authorization: { .init(EKEventStore.authorizationStatus(for: .reminder)) }, request: requestNativeAccess) else {
            #if DEBUG && targetEnvironment(simulator)
            recordAccessDiagnostic("reminders.access.rejected")
            #endif
            throw ReminderAccessError.accessRequired
        }
    }
}

private struct ReminderTransferValue: Sendable {
    let reference: String
    let snapshot: ReminderSnapshot
}
#endif
