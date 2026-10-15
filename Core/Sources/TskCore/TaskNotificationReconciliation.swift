import Foundation

public enum TaskNotificationAuthorization: String, Codable, Sendable {
    case notDetermined, denied, authorized, provisional, ephemeral, unavailable
    public var permitsAlerts: Bool { self == .authorized || self == .provisional || self == .ephemeral }
}

public struct PendingTaskNotification: Sendable {
    public let identifier: String
    public let request: TaskNotificationRequest?
    public let nextTriggerDate: Date?
    public init(identifier: String, request: TaskNotificationRequest?, nextTriggerDate: Date?) {
        self.identifier = identifier; self.request = request; self.nextTriggerDate = nextTriggerDate
    }
}

public protocol TaskNotificationCenter: Sendable {
    func authorization() async throws -> TaskNotificationAuthorization
    func requestAuthorization() async throws -> TaskNotificationAuthorization
    func pending() async throws -> [PendingTaskNotification]
    func add(_ request: TaskNotificationRequest) async throws
    func remove(identifiers: [String]) async
}

public struct TaskNotificationAcceptance: Codable, Sendable {
    public let event: TaskNotificationEvent
    public let effectiveDate: Date
    public let acceptedAt: Date
}

public struct TaskNotificationReport: Codable, Sendable {
    public let authorization: TaskNotificationAuthorization
    public let registered: [TaskNotificationRequest]
    public let unscheduled: [TaskNotificationRequest]
    public let errors: [String]
    public let invalidTaskIDs: [UUID]
    public let checkedAt: Date
    public let timeZoneIdentifier: String
}

public struct TaskNotificationState: Codable, Sendable {
    public var preferences: TaskNotificationPreferences
    public var known: [TaskNotificationEvent]
    public var accepted: [TaskNotificationAcceptance]
    public var lastSuccessfulSynchronization: UUID?
    public var lastReport: TaskNotificationReport?
    public init(preferences: TaskNotificationPreferences = .init()) {
        self.preferences = preferences; known = []; accepted = []; lastSuccessfulSynchronization = nil; lastReport = nil
    }
}

public protocol TaskNotificationStateStore: Sendable {
    func acquireLease() async throws -> any TaskMutationLease
    func load() async throws -> TaskNotificationState
    func save(_ state: TaskNotificationState) async throws
}

public extension TaskManager {
    func notificationState(using store: any TaskNotificationStateStore) async throws -> TaskNotificationState {
        let lease = try await store.acquireLease()
        defer { lease.release() }
        return try await store.load()
    }

    func saveNotificationPreferences(_ preferences: TaskNotificationPreferences, using store: any TaskNotificationStateStore) async throws {
        _ = try Self.notificationPlan(tasks: [], preferences: preferences, at: now())
        let lease = try await store.acquireLease()
        defer { lease.release() }
        var state = try await store.load()
        state.preferences = preferences
        try await store.save(state)
    }

    func reconcileNotifications(center: any TaskNotificationCenter, store: any TaskNotificationStateStore, calendar: Calendar = .autoupdatingCurrent) async throws -> TaskNotificationReport {
        let lease = try await store.acquireLease()
        defer { lease.release() }
        var state = try await store.load()
        var authorization = try await center.authorization()
        var errors: [String] = []
        var registered: [TaskNotificationRequest] = []
        var plan = try await notificationPlan(preferences: state.preferences, calendar: calendar)
        for attempt in 0..<3 {
            let expected = eligibleNotificationRequests(plan.future, accepted: state.accepted, at: now())
            let pending = try await center.pending().filter { $0.identifier.hasPrefix(TaskNotificationRequest.identifierPrefix) }
            let obsolete = pending.filter { pending in !expected.contains { $0.identifier == pending.identifier && $0 == pending.request && $0.fireDate == pending.nextTriggerDate } }.map(\.identifier)
            await center.remove(identifiers: obsolete)
            authorization = try await center.authorization()
            if authorization.permitsAlerts {
                let matching = Set(pending.filter { !obsolete.contains($0.identifier) }.map(\.identifier))
                for request in expected.reversed() where !matching.contains(request.identifier) {
                    do {
                        try await center.add(request)

                    } catch { errors.append(error.localizedDescription) }
                }
            } else {
                await center.remove(identifiers: pending.map(\.identifier))
            }
            var retained = try await center.pending().filter { $0.identifier.hasPrefix(TaskNotificationRequest.identifierPrefix) }
            registered = expected.filter { request in retained.contains { $0.identifier == request.identifier && $0.request == request && $0.nextTriggerDate == request.fireDate } }
            if authorization.permitsAlerts, !registered.isEmpty, registered.count < expected.count {
                let nearest = Array(expected.prefix(registered.count))
                await center.remove(identifiers: retained.filter { pending in !nearest.contains { $0.identifier == pending.identifier } }.map(\.identifier))
                for request in nearest where !registered.contains(request) {
                    do {
                        try await center.add(request)

                    } catch { errors.append(error.localizedDescription) }
                }
                retained = try await center.pending().filter { $0.identifier.hasPrefix(TaskNotificationRequest.identifierPrefix) }
                registered = expected.filter { request in retained.contains { $0.identifier == request.identifier && $0.request == request && $0.nextTriggerDate == request.fireDate } }
            }
            let retainedEvents = Set(registered.flatMap(\.events))
            state.accepted.removeAll { $0.effectiveDate > now() && !retainedEvents.contains($0.event) }
            for request in registered {
                for event in request.events {
                    if let index = state.accepted.firstIndex(where: { $0.event == event }) {
                        if state.accepted[index].effectiveDate > now() {
                            state.accepted[index] = TaskNotificationAcceptance(event: event, effectiveDate: request.fireDate, acceptedAt: state.accepted[index].acceptedAt)
                        }
                    } else { state.accepted.append(TaskNotificationAcceptance(event: event, effectiveDate: request.fireDate, acceptedAt: now())) }
                }
            }
            try await store.save(state)
            let fresh = try await notificationPlan(preferences: state.preferences, calendar: calendar)
            if fresh.future == plan.future { break }
            plan = fresh
            if attempt == 2 {
                await center.remove(identifiers: registered.map(\.identifier))
                registered = []
                errors.append(TaskNotificationError.changedDuringReconciliation.localizedDescription)
            }
        }
        for event in (plan.future + plan.past).flatMap(\.events) where !state.known.contains(event) { state.known.append(event) }
        let report = TaskNotificationReport(authorization: authorization, registered: registered, unscheduled: eligibleNotificationRequests(plan.future, accepted: state.accepted, at: now()).filter { !registered.contains($0) }, errors: errors, invalidTaskIDs: plan.invalidTaskIDs, checkedAt: now(), timeZoneIdentifier: calendar.timeZone.identifier)
        state.lastReport = report
        try await store.save(state)
        return report
    }
}

private func eligibleNotificationRequests(_ requests: [TaskNotificationRequest], accepted: [TaskNotificationAcceptance], at instant: Date) -> [TaskNotificationRequest] {
    let consumed = Set(accepted.filter { $0.effectiveDate <= instant }.map(\.event))
    return requests.compactMap { request in
        let events = request.events.filter { !consumed.contains($0) }
        guard !events.isEmpty else { return nil }
        let kind: TaskNotificationKind = events.count == 2 ? .combined : (events[0].source == .planned ? .planned : .due)
        return TaskNotificationRequest(taskID: request.taskID, title: request.title, kind: kind, fireDate: request.fireDate, events: events)
    }
}
