#if canImport(EventKit)
import Foundation
@preconcurrency import EventKit
import TskCore

public enum CalendarReadError: Error, LocalizedError, Equatable, Sendable {
    case accessRequired, accessNotReady, invalidWindow, invalidEvent
    public var errorDescription: String? {
        switch self {
        case .accessNotReady: "Calendar access has been granted but is not ready yet. Try again."
        case .accessRequired: "Calendar read access is unavailable. Your tasks are still available."
        case .invalidWindow: "Today's Calendar date window is invalid."
        case .invalidEvent: "EventKit returned an event without its calendar, identity, or dates. Try refreshing Calendar."
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
public actor EventKitCalendarSource: CalendarEventSource {
    private let store = EKEventStore()
    private let access = EventKitCalendarAccessObservation()
    #if DEBUG && targetEnvironment(simulator)
    private let diagnosticStoreID = UUID().uuidString
    #endif
    public init() {}

    public func authorization() async -> CalendarReadAuthorization {
        let effective = await access.effectiveAuthorization(authorization: { .init(EKEventStore.authorizationStatus(for: .event)) }, request: requestNativeAccess)
        let value = Self.calendarAuthorization(effective)
        #if DEBUG && targetEnvironment(simulator)
        recordAccessDiagnostic("calendar.authorization", details: ["mappedAuthorization": String(describing: value), "effectiveAuthorization": String(describing: effective)])
        #endif
        return value
    }

    public func requestReadAccess() async throws {
        guard try await access.requestAccess(authorization: { .init(EKEventStore.authorizationStatus(for: .event)) }, request: requestNativeAccess) else { throw CalendarReadError.accessRequired }
        store.reset()
    }

    private func requestNativeAccess() async throws -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        let request = UUID().uuidString
        let context = accessDiagnosticContext
        recordAccessDiagnostic("calendar.access.begin", details: ["request": request])
        do {
            let granted: Bool = try await withCheckedThrowingContinuation { continuation in
                store.requestFullAccessToEvents(completion: Self.accessCallback(continuation, context: context, request: request))
            }
            recordAccessDiagnostic("calendar.access.returned", details: ["request": request, "granted": String(granted)])
            return granted
        } catch {
            let native = error as NSError
            recordAccessDiagnostic("calendar.access.error", details: ["request": request, "errorDomain": native.domain, "errorCode": String(native.code)])
            throw error
        }
        #else
        return try await store.requestFullAccessToEvents()
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private var accessDiagnosticContext: [String: String]? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TSK_UI_ISOLATED_SIMULATOR"] == "1",
              environment["TSK_TEST_REPLICA_NAME"].flatMap(UUID.init(uuidString:)) != nil else { return nil }
        return ["store": diagnosticStoreID]
    }

    private func recordAccessDiagnostic(_ stage: String, details: [String: String]) {
        guard var context = accessDiagnosticContext else { return }
        context.merge(details) { _, value in value }
        context["authorization"] = String(EKEventStore.authorizationStatus(for: .event).rawValue)
        context["rawAuthorization"] = context["authorization"]
        context["mainThread"] = String(Thread.isMainThread)
        TaskParticipantDiagnostics.event(stage, details: context)
    }

    nonisolated private static func accessCallback(_ continuation: CheckedContinuation<Bool, any Error>, context: [String: String]?, request: String) -> @Sendable (Bool, (any Error)?) -> Void {
        { granted, error in
            if var context {
                context["request"] = request
                context["granted"] = String(granted)
                context["mainThread"] = String(Thread.isMainThread)
                context["authorization"] = String(EKEventStore.authorizationStatus(for: .event).rawValue)
                if let native = error as NSError? { context["errorDomain"] = native.domain; context["errorCode"] = String(native.code) }
                TaskParticipantDiagnostics.event("calendar.access.callback", details: context)
            }
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume(returning: granted) }
        }
    }
    #endif

    public func events(in window: DateInterval) async throws -> [CalendarEventSnapshot] {
        try await requireAccess()
        guard window.start.timeIntervalSince1970.isFinite, window.end.timeIntervalSince1970.isFinite, window.duration > 0 else { throw CalendarReadError.invalidWindow }
        store.reset()
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let values = try store.events(matching: predicate).map(Self.snapshot)
        try await requireAccess()
        return values
    }

    private func requireAccess() async throws {
        guard try await access.requireAccess(authorization: { .init(EKEventStore.authorizationStatus(for: .event)) }, request: requestNativeAccess) else { throw CalendarReadError.accessRequired }
    }

    nonisolated private static func calendarAuthorization(_ authorization: EventKitAccessPublication.Authorization) -> CalendarReadAuthorization {
        switch authorization {
        case .notDetermined: .notDetermined
        case .fullAccess: .fullAccess
        case .denied: .denied
        case .restricted: .restricted
        case .writeOnly: .writeOnly
        case .unavailable: .unavailable
        }
    }

    nonisolated static func snapshot(_ event: EKEvent) throws -> CalendarEventSnapshot {
        guard let calendar = event.calendar, let start = event.startDate, let end = event.endDate,
              let identity = event.eventIdentifier, !identity.isEmpty else { throw CalendarReadError.invalidEvent }
        return CalendarEventSnapshot(calendarID: calendar.calendarIdentifier, eventID: identity, title: event.title ?? "", calendarTitle: calendar.title, location: event.location, start: start, end: end, isAllDay: event.isAllDay, isCanceled: event.status == .canceled)
    }
}
#endif
